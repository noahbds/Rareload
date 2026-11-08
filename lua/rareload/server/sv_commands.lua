-- The single `rareload <subcommand>` console command. Replies are English
-- console text for players and admins; toasts carry the localized messages.

RARELOAD.Cmd = RARELOAD.Cmd or {}
local Cmd = RARELOAD.Cmd
Cmd.list = Cmd.list or {}

-- cmdDef = { priv?, usage?, help, fn(ply, args, reply), and what Cmd.Run checks before fn:
--   player? = true or the message: only a player in game may run it (not the server console);
--   target? = true: admins (rareload_manage_saves) may name a player, online or not, first; fn then gets
--             that player (or the SteamID64 of one who is offline) instead of the caller;
--   alive? = true: the player fn gets must be in game and alive;
--   id? = true: args[1] must be a save number, and fn gets it as a number }.
-- Names may be two words ("dev reload").
function Cmd.Register(name, cmdDef)
    assert(isstring(name) and string.Trim(name) ~= "", "Invalid Rareload command name")
    assert(istable(cmdDef) and isfunction(cmdDef.fn), "Invalid Rareload command definition: " .. name)
    name = string.lower(string.Trim(name))
    Cmd.list[name] = cmdDef -- Re-registration is intentional during development reloads.
end

-- The English text of a phrase key ("toast.stuck"), for console replies: read once from the shipped
-- en localization, so the console says what the player's toast says in English. The server has no
-- localization API (the engine loads .properties files on the client only).
local english
function Cmd.Phrase(key, ...)
    if not english then
        english = {}
        local text = file.Read("resource/localization/en/rareload.properties", "GAME") or ""
        for line in string.gmatch(text, "[^\r\n]+") do
            local phraseKey, phrase = string.match(line, "^rareload%.([^=%s]+)=(.*)$")
            if phraseKey then
                -- \uXXXX is the format's only escape.
                english[phraseKey] = string.gsub(phrase, "\\u(%x%x%x%x)",
                    function(hex) return utf8.char(tonumber(hex, 16)) end)
            end
        end
    end
    local phrase = english[key] or key
    if select("#", ...) == 0 then return phrase end
    local ok, out = pcall(string.format, phrase, ...)
    return ok and out or phrase
end

local function replyTo(ply)
    return function(msg)
        msg = tostring(msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end
end

-- Runs `rareload <args…>` for `ply` (nil = the server console).
function Cmd.Run(ply, args)
    args = istable(args) and table.Copy(args) or {}
    local reply = replyTo(ply)
    local name = string.lower(args[1] or "help")
    if args[2] and Cmd.list[name .. " " .. string.lower(args[2])] then
        name = name .. " " .. string.lower(table.remove(args, 2))
    end
    table.remove(args, 1)

    local cmdDef = Cmd.list[name]
    if not cmdDef then return reply("Unknown command. Type 'rareload help'.") end
    local who = IsValid(ply) and ply:Nick() or "Console"
    local line = "rareload " .. name .. (#args > 0 and " " .. table.concat(args, " ") or "")
    if cmdDef.priv and not RARELOAD.Can(ply, cmdDef.priv) then
        RARELOAD.Log("commands", ply):verbose("%s tried '%s' without %s", who, line, cmdDef.priv)
        return reply("You need the " .. cmdDef.priv .. " privilege for this.")
    end
    RARELOAD.Log("commands", ply):verbose("%s ran '%s'", who, line)

    local actor = ply
    if cmdDef.target then
        actor = Cmd.Target(ply, args, reply, name)
        if not actor then return end
    elseif cmdDef.player and not IsValid(ply) then
        return reply(isstring(cmdDef.player) and cmdDef.player or "Only players have saves.")
    end
    if cmdDef.alive then
        if isstring(actor) then return reply("That player is offline: saves are restored only for players in game.") end
        if not actor:Alive() then return reply("Respawn first, then restore the save.") end
    end
    if cmdDef.id then
        local id = Cmd.SaveID(args[1])
        if not id then return reply("Usage: rareload " .. name .. " " .. (cmdDef.usage or "<save number>")) end
        args[1] = id
    end

    local ok, err = xpcall(function() cmdDef.fn(actor, args, reply) end, debug.traceback)
    if not ok then
        RARELOAD.Log("commands", ply):error("'%s' (run by %s) failed: %s", line, who, tostring(err))
        reply("An internal error occurred while executing this command. Check the server log.")
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
            local cmdDef = Cmd.list[name]
            if not cmdDef.priv or RARELOAD.Can(ply, cmdDef.priv) then
                local usage = cmdDef.usage and " " .. cmdDef.usage or ""
                reply(string.format("  rareload %-24s %s", name .. usage, cmdDef.help))
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
    player = "Only players can save.",
    fn = function(ply) RARELOAD.Pipeline.Save(ply, { reason = "command" }) end,
})

Cmd.Register("settings", {
    help = "Show every setting, its convar and your effective value",
    fn = function(ply, _, reply)
        local keys = table.GetKeys(RARELOAD.Settings)
        table.sort(keys)
        for _, key in ipairs(keys) do
            local settingDef = RARELOAD.Settings[key]
            local names = settingDef.convar .. (settingDef.pref and " / " .. settingDef.pref or "")
            -- Client settings only exist on each client; the server can't read them.
            local value = settingDef.scope == "client" and "(client)" or RARELOAD.Get(ply, key)
            if settingDef.type == "float" and isnumber(value) then value = string.format("%g", math.Round(value, 3)) end
            reply(string.format("  %-22s %-8s %s", key, tostring(value), names))
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
    help = "Show which Rareload privileges you have, and the tier each one is for",
    fn = function(ply, _, reply)
        local names = table.GetKeys(RARELOAD.Privs)
        table.sort(names)
        for _, name in ipairs(names) do
            reply(string.format("  %-3s %-36s %-10s %s", RARELOAD.Can(ply, name) and "yes" or "no", name,
                RARELOAD.Tier(name), RARELOAD.Privs[name].desc))
        end
        if CAMI then reply("An admin mod is installed: what it grants comes before these tiers.") end
        if RARELOAD.Can(ply, "rareload_settings") then
            for sid64, list in SortedPairs(RARELOAD.Grants()) do
                local who = player.GetBySteamID64(sid64)
                reply("  " .. sid64 .. (who and " (" .. who:Nick() .. ")" or "") .. " also has: " .. list)
            end
        end
    end,
})

local TIER_WORDS = { user = true, admin = true, superadmin = true, default = true }

Cmd.Register("perms set", {
    priv = "rareload_settings",
    usage = "<privilege> <user|admin|superadmin|default> or <privilege> <player> [off]",
    help = "Choose who has a privilege when no admin mod manages it: a tier, or one player",
    fn = function(ply, args, reply)
        local name = args[1] or ""
        if not RARELOAD.Privs[name] then name = "rareload_" .. name end
        if not RARELOAD.Privs[name] then return reply("No such privilege. Type 'rareload perms' for the list.") end
        local by = IsValid(ply) and ply:Nick() or "Console"
        local note = CAMI and " (an admin mod is installed: what it grants comes first)" or ""

        local who = args[2] or ""
        if TIER_WORDS[string.lower(who)] then
            local ok, why = RARELOAD.SetTier(name, string.lower(who))
            if not ok then return reply(why) end
            RARELOAD.Log("perms", ply):info("%s set %s to %s", by, name, RARELOAD.Tier(name))
            return reply(name .. " is now for: " .. RARELOAD.Tier(name) .. note)
        end

        -- One player: by name or SteamID when online, by SteamID64 when not.
        local target, findError = Cmd.FindPlayer(who)
        local sid64 = target and target:SteamID64() or (who:match("^7656119%d%d%d%d%d%d%d%d%d%d$") and who)
        if not sid64 then
            return reply(findError
                or "Give a tier (user, admin, superadmin, default), a player's name or a 17-digit SteamID64.")
        end
        if args[3] and string.lower(args[3]) ~= "off" then return reply("The only optional value is 'off'.") end
        local on = string.lower(args[3] or "") ~= "off"
        local ok, why = RARELOAD.Grant(sid64, name, on)
        if not ok then return reply(why) end
        local label = target and target:Nick() or sid64
        RARELOAD.Log("perms", ply):info("%s %s %s %s %s", by, on and "gave" or "took", name, on and "to" or "from",
            label)
        reply(label .. (on and " now has " or " no longer has ") .. name .. (on and "" or " of their own") .. note)
    end,
})

-- The timeline from the console (the Save Timeline window does the same with buttons).

-- Exact identifiers/names win; partial names must identify exactly one player.
function Cmd.FindPlayer(text)
    if not isstring(text) or text == "" then return nil, "Name a player." end
    local lower, matches = string.lower(text), {}
    for _, candidate in player.Iterator() do
        if candidate:SteamID64() == text or candidate:SteamID() == text or string.lower(candidate:Nick()) == lower then
            return candidate
        end
    end
    for _, candidate in player.Iterator() do
        if string.find(string.lower(candidate:Nick()), lower, 1, true) then matches[#matches + 1] = candidate end
    end
    if #matches == 1 then return matches[1] end
    if #matches > 1 then
        local names = {}
        for _, candidate in ipairs(matches) do names[#names + 1] = candidate:Nick() end
        return nil, "Multiple players match \"" .. text .. "\": " .. table.concat(names, ", ")
    end
    return nil, "Player not found: " .. text
end

-- A player who is offline but has saves on this map: by SteamID64, STEAM_ ID, or the name they last
-- saved with (A3). Returns their SteamID64.
local function offlineTarget(text)
    local sid = text:match("^7656119%d+$") or (text:match("^STEAM_%d:%d:%d+$") and util.SteamIDTo64(text))
    if sid then return sid end
    local lower, found = string.lower(text), {}
    for _, name in ipairs(file.Find("rareload/" .. RARELOAD.Store.MapDir() .. "/*.json", "DATA") or {}) do
        local id = name:match("^(%d+)%.json$")
        local doc = id and RARELOAD.History.Doc(id)
        if doc and doc.nick and string.find(string.lower(doc.nick), lower, 1, true) then found[#found + 1] = id end
    end
    if #found == 1 then return found[1] end
end

-- For `target` commands (A3): admins (rareload_manage_saves) can name a player, online or not, as the
-- first argument. Returns the player when online, else their SteamID64, or nil (`reply` told why).
-- Acting on someone else's saves is logged.
function Cmd.Target(ply, args, reply, name)
    if not (args[1] and not tonumber(args[1])) then
        if IsValid(ply) then return ply end
        return reply("Name a player.")
    end
    if not RARELOAD.Can(ply, "rareload_manage_saves") then
        return reply("You need the rareload_manage_saves privilege to act on other players' saves.")
    end
    local text = table.remove(args, 1)
    local target, err = Cmd.FindPlayer(text)
    target = target or offlineTarget(text)
    if not target then return reply(err or ("Player not found: " .. text)) end
    RARELOAD.Log("admin", ply):info("%s ran 'rareload %s' on the saves of %s", IsValid(ply) and ply:Nick()
        or "Console", name, isstring(target) and target or target:Nick())
    return target
end

-- A save number typed in the console, or nil.
function Cmd.SaveID(value)
    local id = tonumber(value)
    return id and id >= 1 and id < math.huge and id == math.floor(id) and id or nil
end

local function result(reply, ok, what)
    reply(ok and ("Done: " .. what) or ("Failed: " .. what .. ". Check the save ID and try again."))
end

Cmd.Register("history", {
    priv = "rareload_restore",
    usage = "[player]",
    help = "List saves on this map (* = respawn point, P = pinned); admins can name a player",
    target = true,
    fn = function(target, _, reply)
        for _, row in ipairs(RARELOAD.History.Rows(target)) do
            reply(string.format("  %s%s No. %-4d %s  %-10s %s%s", row.active and "*" or " ", row.pinned and "P" or " ",
                row.id, os.date("%Y-%m-%d %H:%M:%S", row.time), row.reason, table.concat(row.modules, ","),
                row.note and ("  \"" .. row.note .. "\"") or ""))
        end
    end,
})

Cmd.Register("history restore", {
    priv = "rareload_restore",
    usage = "[player] <id> [" .. table.concat(RARELOAD.COMPONENT_ORDER, ",") .. "] [exact]",
    help = "Restore a save now (all components by default); exact also removes your objects not in it",
    target = true, alive = true, id = true,
    fn = function(ply, args, reply)
        local exact = false
        for i = #args, 2, -1 do
            if string.lower(args[i]) == "exact" then
                exact = true
                table.remove(args, i)
            end
        end
        local comps = RARELOAD.History.ParseComps(args[2])
        result(reply, RARELOAD.History.Restore(ply, args[1], comps, { exact = exact }), "restore")
    end,
})

Cmd.Register("history activate", {
    priv = "rareload_restore",
    usage = "[player] <id>",
    help = "Make a save your respawn point",
    target = true, id = true,
    fn = function(ply, args, reply) result(reply, RARELOAD.History.Activate(ply, args[1]), "activate") end,
})

Cmd.Register("history undo", {
    priv = "rareload_restore",
    help = "Undo the last restore",
    player = true,
    fn = function(ply, _, reply) result(reply, RARELOAD.History.Undo(ply), "undo") end,
})

Cmd.Register("history pin", {
    priv = "rareload_restore",
    usage = "[player] <id> [0]",
    help = "Pin a save so it's never pruned (0 unpins)",
    target = true, id = true,
    fn = function(ply, args, reply)
        if args[2] and args[2] ~= "0" then return reply("Usage: rareload history pin [player] <id> [0]") end
        result(reply, RARELOAD.History.SetPinned(ply, args[1], args[2] ~= "0"), "pin")
    end,
})

Cmd.Register("history note", {
    priv = "rareload_restore",
    usage = "[player] <id> <text>",
    help = "Attach a note to a save",
    target = true, id = true,
    fn = function(ply, args, reply)
        local id = table.remove(args, 1)
        local note = string.sub(table.concat(args, " "), 1, 256)
        if note == "" then return reply("Usage: rareload history note [player] <id> <text>") end
        result(reply, RARELOAD.History.SetNote(ply, id, note), "note")
    end,
})

Cmd.Register("history delete", {
    priv = "rareload_restore",
    usage = "[player] <id>",
    help = "Delete a save",
    target = true, id = true,
    fn = function(ply, args, reply) result(reply, RARELOAD.History.Delete(ply, args[1]), "delete") end,
})

Cmd.Register("history clear", {
    priv = "rareload_restore",
    usage = "[player]",
    help = "Delete every save except pinned ones and the respawn point; admins can name a player",
    target = true,
    fn = function(target, _, reply) result(reply, RARELOAD.History.Clear(target), "clear") end,
})

Cmd.Register("history reload", {
    priv = "rareload_use_tool",
    usage = "<" .. table.concat(RARELOAD.RELOAD_MODES, "|") .. "> [components]",
    help = "Choose what the tool's reload key does",
    player = true,
    fn = function(ply, args, reply)
        if not RARELOAD.History.SetReloadConfig(ply, args[1], RARELOAD.History.ParseComps(args[2])) then
            return reply("Unknown mode.")
        end
        reply("Reload key: " .. args[1])
    end,
})

local function coords(args)
    local posX, posY, posZ = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if not posX or not posY or not posZ or posX ~= posX or posY ~= posY or posZ ~= posZ
        or math.abs(posX) == math.huge or math.abs(posY) == math.huge or math.abs(posZ) == math.huge then return nil end
    local target = RARELOAD.Util.ToVector({ posX, posY, posZ })
    return target and util.IsInWorld(target) and target or nil
end

Cmd.Register("tp", {
    priv = "rareload_teleport",
    usage = "<x> <y> <z>",
    help = "Teleport to a position",
    player = true,
    fn = function(ply, args, reply)
        local pos = coords(args)
        if not pos then return reply("Not a position inside the map.") end
        if ply:InVehicle() then ply:ExitVehicle() end
        ply:SetPos(pos)
        ply:SetLocalVelocity(vector_origin)
    end,
})

Cmd.Register("lookat", {
    priv = "rareload_teleport",
    usage = "<x> <y> <z>",
    help = "Turn to face a position",
    player = true,
    fn = function(ply, args, reply)
        local pos = coords(args)
        if not pos then return reply("Not a position inside the map.") end
        ply:SetEyeAngles((pos - ply:EyePos()):Angle())
    end,
})

Cmd.Register("antistuck test", {
    priv = "rareload_anti_stuck",
    usage = "[player]",
    help = "Look for a free spot from where a player stands (debug draws the candidates)",
    fn = function(ply, args, reply)
        local target = ply
        if args[1] then
            local err
            target, err = Cmd.FindPlayer(args[1])
            if not target then return reply(err) end
        end
        if not IsValid(target) then return reply("Name a player when running this from the server console.") end
        if target ~= ply and not RARELOAD.Can(ply, "rareload_admin") then
            return reply("Only admins can test anti-stuck on another player.")
        end
        local AntiStuck = RARELOAD.AntiStuck
        local pos, crouched = target:GetPos(), target:Crouching()
        local stuck, why = AntiStuck.IsStuck(pos, target, crouched)
        local tried, started = 0, SysTime()
        local mins, maxs = target:OBBMins(), target:OBBMaxs()
        local found, method = AntiStuck.Resolve(pos, target, crouched, function(spot, free)
            tried = tried + 1
            if RARELOAD.Get(nil, "debug") and tried <= 200 then -- G83
                debugoverlay.Box(spot, mins, maxs, 8, free and Color(0, 255, 0, 30) or Color(255, 0, 0, 8))
            end
        end)
        reply(string.format("Here: %s. Free spot: %s (%s), %d candidates, %.0f ms.",
            stuck and ("stuck, " .. why) or "free", found and tostring(found) or "none", method or "-",
            tried, (SysTime() - started) * 1000))
    end,
})

Cmd.Register("antistuck method", {
    priv = "rareload_anti_stuck",
    usage = "[list|enable|disable|only|up|down|reset] [method]",
    help = "Show or change which anti-stuck methods run, and in which order",
    fn = function(ply, args, reply)
        local action = args[1] or "list"
        if action ~= "list" then
            local ok, err = RARELOAD.AntiStuck.Configure(action, args[2])
            if not ok then return reply("Failed: " .. err) end
            RARELOAD.Log("antistuck", ply):info("%s: anti-stuck method %s %s", IsValid(ply) and ply:Nick() or "Console",
                tostring(args[2] or "all"), action)
        end
        for i, method in ipairs(RARELOAD.AntiStuck.List()) do
            reply(string.format("  %d. [%s] %s", i, method.enabled and "on " or "off", method.id))
        end
    end,
})

Cmd.Register("data cleanup", {
    priv = "rareload_data_cleanup",
    usage = "[all]",
    help = "Delete saved world data no save uses any more, on this map (or every map with 'all')",
    fn = function(ply, args, reply)
        local all = args[1] == "all"
        local removed = all and RARELOAD.Store.GCAll() or RARELOAD.Store.GC()
        RARELOAD.Log("admin", ply):info("%s cleaned up unused data%s: %d blobs", IsValid(ply) and ply:Nick() or
            "Console", all and " on every map" or "", removed)
        reply("Removed " .. removed .. " unused blobs" .. (all and " on every map." or "."))
    end,
})

Cmd.Register("data usage", {
    priv = "rareload_data_cleanup",
    help = "What the saves take on disk: by map, by player, unused data and the biggest saves",
    fn = function(_, _, reply)
        for _, line in ipairs(RARELOAD.Store.UsageLines(RARELOAD.Store.Overview())) do reply(line) end
    end,
})

Cmd.Register("data prune", {
    priv = "rareload_data_cleanup",
    usage = "<days>",
    help = "Delete saves older than this many days on every map (pinned saves and respawn points are kept)",
    fn = function(ply, args, reply)
        local days = tonumber(args[1])
        if not days or days < 1 or days ~= math.floor(days) then return reply("Usage: rareload data prune <days>") end
        local removed = RARELOAD.Store.Prune(days)
        RARELOAD.Log("admin", ply):info("%s deleted %d saves older than %d days", IsValid(ply) and ply:Nick() or
            "Console", removed, days)
        reply("Deleted " .. removed .. " saves older than " .. days .. " days.")
    end,
})

-- Quick commands (5.4 plan, D3): the same as the quick keys and the reload key, from the console -----------
-- The toast on screen says why one didn't happen.
local function quickResult(reply, ok, what)
    reply(ok and ("Done: " .. what) or ("Not done: " .. what .. " (the message on screen says why)."))
end

Cmd.Register("restore", {
    priv = "rareload_restore",
    usage = "[" .. table.concat(RARELOAD.COMPONENT_ORDER, ",") .. "]",
    help = "Restore your respawn point now (all components by default)",
    player = true,
    fn = function(ply, args, reply)
        quickResult(reply, RARELOAD.History.RestoreActive(ply, RARELOAD.History.ParseComps(args[1])), "restore")
    end,
})

Cmd.Register("back", {
    priv = "rareload_restore",
    help = "Restore the save before your respawn point, which becomes your respawn point",
    player = true,
    fn = function(ply, _, reply) quickResult(reply, RARELOAD.History.Back(ply), "back") end,
})

Cmd.Register("death", {
    priv = "rareload_restore",
    help = "Go back to the save made when you last died (needs \"Save when dying\")",
    player = true,
    fn = function(ply, _, reply)
        quickResult(reply, RARELOAD.Death.Back(ply), "back to before you died")
    end,
})

Cmd.Register("quicksave", {
    priv = "rareload_save",
    help = "Save into your quick slot (the quick save key does the same)",
    player = true,
    fn = function(ply, _, reply) quickResult(reply, RARELOAD.History.QuickSave(ply), "quicksave") end,
})

Cmd.Register("quickload", {
    priv = "rareload_restore",
    help = "Restore your quick slot (the quick load key does the same)",
    player = true,
    fn = function(ply, _, reply) quickResult(reply, RARELOAD.History.QuickLoad(ply), "quickload") end,
})

-- Checkpoints (sv_checkpoints.lua) -----------------------------------------------------------------------

local function checkpointReply(reply, ok, key, args)
    reply((ok and "" or "Not done: ") .. Cmd.Phrase(key, unpack(args or {})))
end

Cmd.Register("checkpoint list", {
    priv = "rareload_checkpoints",
    help = "List your checkpoints on this map",
    player = true,
    fn = function(ply, _, reply)
        local list = RARELOAD.Checkpoints.List(ply)
        if #list == 0 then return reply("You have no checkpoints on this map.") end
        for i, checkpoint in ipairs(list) do
            reply(string.format("  %d. %s  (%.0f, %.0f, %.0f)", i, checkpoint.name, checkpoint.pos[1],
                checkpoint.pos[2], checkpoint.pos[3]))
        end
    end,
})

Cmd.Register("checkpoint add", {
    priv = "rareload_checkpoints",
    usage = "[name]",
    help = "Set a checkpoint where you stand (an existing name moves it)",
    player = true,
    fn = function(ply, args, reply)
        checkpointReply(reply, RARELOAD.Checkpoints.Add(ply, table.concat(args, " ")))
    end,
})

Cmd.Register("checkpoint go", {
    priv = "rareload_checkpoints",
    usage = "<name or number>",
    help = "Teleport to one of your checkpoints",
    player = true,
    fn = function(ply, args, reply)
        checkpointReply(reply, RARELOAD.Checkpoints.Go(ply, table.concat(args, " ")))
    end,
})

Cmd.Register("checkpoint remove", {
    priv = "rareload_checkpoints",
    usage = "<name or number>",
    help = "Delete one of your checkpoints",
    player = true,
    fn = function(ply, args, reply)
        checkpointReply(reply, RARELOAD.Checkpoints.Remove(ply, table.concat(args, " ")))
    end,
})

-- Server snapshots and rollback (sv_snapshots.lua) --------------------------------------------------------

Cmd.Register("snapshot", {
    priv = "rareload_rollback",
    help = "Take a server snapshot of every player's objects now",
    fn = function(ply, _, reply)
        local ok = RARELOAD.Snapshots.Take(function(snap)
            local text = "Snapshot No. " .. snap.id .. ": " .. table.Count(snap.players) .. " players."
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, text) else print(text) end
        end)
        if not ok then reply("A snapshot is already being taken.") end
    end,
})

Cmd.Register("snapshots", {
    priv = "rareload_rollback",
    help = "List the server snapshots of this map",
    fn = function(_, _, reply)
        local list = RARELOAD.Snapshots.List()
        if #list == 0 then return reply("No snapshots on this map. Set sv_rareload_snapshot_interval to take them.") end
        for _, snapshot in ipairs(list) do
            local names = {}
            for _, part in pairs(snapshot.players) do names[#names + 1] = part.nick end
            reply(string.format("  #%d  %s  (%d min ago)  %s", snapshot.id, os.date("%Y-%m-%d %H:%M", snapshot.time),
                math.floor((os.time() - snapshot.time) / 60), table.concat(names, ", ")))
        end
    end,
})

Cmd.Register("rollback", {
    priv = "rareload_rollback",
    usage = "<minutes|#id> [player]",
    help = "Put players' objects back as they were in a snapshot (the newest one at least that old, or #id)",
    fn = function(ply, args, reply)
        local snap = RARELOAD.Snapshots.Find(args[1])
        if not snap then return reply("No such snapshot. Type 'rareload snapshots' for the list.") end
        local only
        if args[2] then
            local target = Cmd.FindPlayer(table.concat(args, " ", 2))
            if not target then return reply("That player is not in game.") end
            only = target:SteamID64()
        end
        local restored, skipped = RARELOAD.Snapshots.Rollback(snap, only)
        RARELOAD.Log("admin", ply):info("%s rolled back to snapshot No. %d: %d players%s",
            IsValid(ply) and ply:Nick() or "Console", snap.id, restored,
            #skipped > 0 and (", not: " .. table.concat(skipped, ", ")) or "")
        reply("Rolled back " .. restored .. " players to snapshot No. " .. snap.id
            .. (#skipped > 0 and (" (not in game or dead: " .. table.concat(skipped, ", ") .. ")") or "") .. ".")
    end,
})

Cmd.Register("recover", {
    priv = "rareload_restore",
    help = "After a server crash: get your objects back from the last snapshot, when it is newer than your save",
    player = true,
    fn = function(ply, _, reply) quickResult(reply, RARELOAD.Snapshots.Recover(ply), "recover") end,
})

-- Blocked classes (sv_exclude.lua) ----------------------------------------------------------------------

Cmd.Register("block list", {
    priv = "rareload_block_classes",
    help = "List the object classes Rareload never saves or restores",
    fn = function(_, _, reply)
        local list = RARELOAD.Blocked.List()
        if #list == 0 then return reply("No classes are blocked.") end
        reply(#list .. " blocked: " .. table.concat(list, ", "))
    end,
})

local function blockCommand(name, add)
    Cmd.Register("block " .. name, {
        priv = "rareload_block_classes",
        usage = "<class>",
        help = add and "Never save or restore objects of this class" or "Save and restore this class again",
        fn = function(ply, args, reply)
            local ok, what = (add and RARELOAD.Blocked.Add or RARELOAD.Blocked.Remove)(args[1])
            if not ok then return reply("Failed: " .. what) end
            RARELOAD.Log("exclude", ply):info("%s %s the class %s", IsValid(ply) and ply:Nick() or "Console",
                add and "blocked" or "unblocked", what)
            reply((add and "Blocked " or "Unblocked ") .. what .. ".")
        end,
    })
end
blockCommand("add", true)
blockCommand("remove", false)

-- Export, import and share saves (sv_share.lua) ------------------------------------------------------

Cmd.Register("export", {
    priv = "rareload_export",
    usage = "<id> [file name]",
    help = "Write a save to data/rareload/exports on the server (in singleplayer: your own data folder)",
    player = true, id = true,
    fn = function(ply, args, reply)
        local entry = RARELOAD.History.Get(ply, args[1])
        if not entry then return reply("No such save. Type 'rareload history' for the list.") end
        local path = RARELOAD.Share.WriteFile(ply, entry, args[2])
        reply(path and ("Exported to " .. path) or "Export failed; check the server log.")
    end,
})

Cmd.Register("import", {
    priv = "rareload_import",
    usage = "<file name>",
    help = "Add a save from data/rareload/exports on the server to your timeline",
    player = true,
    fn = function(ply, args, reply)
        local name = RARELOAD.Store.Clean(string.gsub(args[1] or "", "%.json$", ""))
        if name == "" then return reply("Name a file from data/rareload/exports.") end
        local doc = RARELOAD.Share.ReadFile(name)
        if not doc then return reply("No such file: data/rareload/exports/" .. name .. ".json") end
        local ok, idOrWhy, dropped = RARELOAD.Share.ImportAndTell(ply, doc)
        if not ok then return reply("Failed: " .. idOrWhy) end
        dropped = istable(dropped) and dropped or {}
        local left = #dropped > 0 and ". Left out: " .. table.concat(dropped, ", ") or "."
        reply("Imported as save No. " .. idOrWhy .. left)
    end,
})

Cmd.Register("share", {
    priv = "rareload_share",
    usage = "<id> <player>",
    help = "Offer a copy of one of your saves to another player",
    player = true, id = true,
    fn = function(ply, args, reply)
        if not args[2] then return reply("Usage: rareload share <id> <player>") end
        local target, err = Cmd.FindPlayer(table.concat(args, " ", 2))
        if not target then return reply(err) end
        local ok, why = RARELOAD.Share.Offer(ply, args[1], target)
        reply(ok and "Offer sent." or "Failed: " .. tostring(why))
    end,
})

-- Inventories (sv_inventory.lua) ----------------------------------------------------------------------

-- "global" or a save number. Returns ok, save.
local function inventoryTarget(arg)
    if arg == "global" then return true, nil end
    local number = tonumber(arg)
    if number and number >= 1 and number < math.huge and number == math.floor(number) then return true, number end
    return false
end

-- An inventory file of the player: data/rareload/inventories/<SteamID64>/<name>.
local function inventoryFile(ply, name)
    local key = RARELOAD.Util.PlayerKey(ply)
    name = RARELOAD.Store.Clean(name or "inventory")
    return key and ("inventories/" .. key .. "/" .. (name ~= "" and name or "inventory")) or nil
end

-- fn(ply, save, args, reply) may return a toast key, its arguments and whether it worked.
local function inventoryCommand(name, usage, help, fn)
    Cmd.Register(name, {
        priv = "rareload_manage_inventory",
        usage = usage,
        help = help,
        player = "Only players have inventories.",
        fn = function(ply, args, reply)
            local ok, save = inventoryTarget(args[1])
            if not ok then return reply("Usage: rareload " .. name .. " " .. usage) end
            local key, targs, worked = fn(ply, save, args, reply)
            if key then RARELOAD.Toast(ply, key, targs, worked == false and "error" or "ok") end
            if name ~= "inventory export" and worked ~= false then RARELOAD.Inventory.Push(ply, save) end
        end,
    })
end

inventoryCommand("inventory export", "<save number|global> [file name]",
    "Write an inventory to data/rareload/inventories/<your SteamID64>/", function(ply, save, args, reply)
        local Inventory = RARELOAD.Inventory
        local inv, _, exists = Inventory.Read(ply, save)
        local rel = inventoryFile(ply, args[2])
        if not exists or not rel then return reply("Failed: " .. Inventory.TargetName(save) .. " does not exist.") end
        RARELOAD.Store.Save(rel, inv or Inventory.Empty())
        reply("Exported " .. Inventory.TargetName(save) .. " to data/rareload/" .. rel .. ".json")
    end)

inventoryCommand("inventory import", "<save number|global> [file name]",
    "Replace an inventory with one from data/rareload/inventories/<your SteamID64>/", function(ply, save, args, reply)
        local Inventory = RARELOAD.Inventory
        local rel = inventoryFile(ply, args[2])
        local data = rel and RARELOAD.Store.Load(rel, true)
        if not data then return reply("Failed: there is no data/rareload/" .. tostring(rel) .. ".json") end
        local key, targs, ok = Inventory.SetFrom(ply, save, data, "import")
        reply(ok and ("Imported into " .. Inventory.TargetName(save) .. ".")
            or ("Failed: " .. tostring(targs and targs[1])))
        return key, targs, ok
    end)

inventoryCommand("inventory give", "<save number|global>", "Give yourself an inventory now", function(ply, save)
    return RARELOAD.Inventory.GiveTarget(ply, save)
end)

-- Subcommands the client runs (its windows and world display).
local CLIENT_COMMANDS = {
    timeline = { help = "Open the Save Timeline" },
    menu = { usage = "[server|client]", help = "Open the Rareload settings" },
    highlight = { usage = "<all|link|players|clear>", help = "Highlight saved objects and players (world display)" },
    preview = { usage = "off", help = "Hide the Save Timeline preview" },
    inventory = { priv = "rareload_manage_inventory", help = "Open the inventory manager" },
    checkpoints = { priv = "rareload_checkpoints", help = "Open your checkpoints" },
}
for name, cmdDef in pairs(CLIENT_COMMANDS) do
    local commandName = name
    cmdDef.player = true
    cmdDef.fn = function(ply, args) RARELOAD.Net.Push(ply, "cmd", { name = commandName, args = args }) end
    Cmd.Register(commandName, cmdDef)
end

-- Log and status (sv_log.lua, sv_status.lua) ---------------------------------------------------------

local LEVEL_TAGS = { error = "ERROR", warn = "WARN", info = "", verbose = "debug" }

local function printLog(reply, count, filter)
    local events = RARELOAD.LogRecent(count, filter)
    if #events == 0 then
        return reply(filter and filter ~= "" and ("Nothing in the log matches \"" .. filter .. "\".")
            or "The log is empty.")
    end
    local day
    for _, event in ipairs(events) do
        local date = os.date("%Y-%m-%d", event.t)
        if date ~= day then
            day = date
            reply("-- " .. date)
        end
        reply(string.format("%s %-5s %-9s %s", os.date("%H:%M:%S", event.t), LEVEL_TAGS[event.level] or event.level,
            tostring(event.category), event.text))
    end
    reply(string.format("(%d lines; 'rareload log <count> <filter>' to see more or fewer)", #events))
end

Cmd.Register("log", {
    priv = "rareload_debug",
    usage = "[count] [errors|warnings|activity|debug] [category|player|text]",
    help = "Show what Rareload logged, newest last: e.g. 'rareload log 50 errors' or 'rareload log Noah restore'",
    fn = function(_, args, reply)
        local count = 40
        if tonumber(args[1]) then count = math.Clamp(math.floor(tonumber(table.remove(args, 1))), 1, 1000) end
        printLog(reply, count, table.concat(args, " "))
    end,
})

Cmd.Register("log clear", {
    priv = "rareload_debug",
    help = "Empty the in-game log (log files are kept)",
    fn = function(ply, _, reply)
        RARELOAD.LogClear()
        RARELOAD.Log("commands", ply):info("%s cleared the log", IsValid(ply) and ply:Nick() or "Console")
        reply("Log cleared.")
    end,
})

Cmd.Register("log level", {
    priv = "rareload_settings",
    usage = "<errors|warnings|activity|debug>",
    help = "Choose what Rareload prints to the server console",
    fn = function(ply, args, reply)
        local level = string.lower(args[1] or "")
        if not table.HasValue(RARELOAD.Settings.logLevel.values, level) then
            return reply("Current level: " .. RARELOAD.Get(nil, "logLevel")
                .. ". Usage: rareload log level <errors|warnings|activity|debug>")
        end
        RARELOAD.Settings.logLevel.cv:SetString(level)
        RARELOAD.Log("settings", ply):info("%s set the log level to %s", IsValid(ply) and ply:Nick() or "Console",
            level)
        reply("Log level: " .. level .. ".")
    end,
})

Cmd.Register("status", {
    priv = "rareload_debug",
    help = "What Rareload found on this server: supported addons, saves, settings, logging",
    fn = function(_, _, reply)
        for _, line in ipairs(RARELOAD.Status.Lines()) do reply(line) end
        local methods = {}
        for _, method in ipairs(RARELOAD.AntiStuck.List()) do
            if method.enabled then methods[#methods + 1] = method.id end
        end
        reply("  Anti-stuck: " .. (#methods > 0 and table.concat(methods, " > ") or "every method is off"))
    end,
})

Cmd.Register("debug", {
    priv = "rareload_debug",
    usage = "<on|off|recent [n]|clear|diag>",
    help = "Turn debug on or off; recent, clear and diag are 'rareload log', 'log clear' and 'status'",
    fn = function(ply, args, reply)
        local sub = args[1] or "diag"
        if sub == "on" or sub == "off" then
            RARELOAD.Settings.debug.cv:SetString(sub == "on" and "1" or "0")
            RARELOAD.Log("settings", ply):info("%s turned debug %s", IsValid(ply) and ply:Nick() or "Console", sub)
            reply("Debug " .. sub .. ".")
        elseif sub == "recent" then
            printLog(reply, math.Clamp(tonumber(args[2]) or 30, 1, 1000))
        elseif sub == "clear" then
            Cmd.Run(ply, { "log", "clear" })
        elseif sub == "diag" then
            Cmd.Run(ply, { "status" })
        else
            reply("Usage: rareload debug <on|off|recent [n]|clear|diag>")
        end
    end,
})

-- In-game checks of engine behaviour the offline tests can only stub (§27.4).
local SELFTEST = {
    { "JSON keeps Vectors", function()
        local decoded = util.JSONToTable(util.TableToJSON({ v = Vector(1, 2, 3) }))
        return decoded and isvector(decoded.v) and decoded.v == Vector(1, 2, 3)
    end },
    { "Compress round-trip with maxSize", function()
        local text = string.rep("rareload", 1000)
        return util.Decompress(util.Compress(text), #text) == text
    end },
    { "Storage write and read back", function()
        local rel = "selftest_" .. math.floor(SysTime() * 1000000) .. "_" .. math.random(1, 999999)
        local ok, value = pcall(function()
            RARELOAD.Store.Save(rel, { v = RARELOAD.Store.SCHEMA, value = 42 })
            RARELOAD.Store.Flush()
            RARELOAD.Store.Forget(rel)
            return (RARELOAD.Store.Load(rel) or {}).value == 42
        end)
        pcall(RARELOAD.Store.Delete, rel)
        pcall(RARELOAD.Store.Flush)
        RARELOAD.Store.Forget(rel)
        return ok and value == true
    end },
    { "Every module is in a known phase", function()
        return pcall(RARELOAD.Pipeline.Order, table.ClearKeys(RARELOAD.Pipeline.Defs()))
    end },
}

Cmd.Register("selftest", {
    priv = "rareload_debug",
    help = "Check engine behaviour Rareload depends on",
    fn = function(_, _, reply)
        local failed = 0
        for _, check in ipairs(SELFTEST) do
            local ok, passed = pcall(check[2])
            local pass = ok and passed == true
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
        local ok, err = pcall(include, "autorun/rareload.lua")
        if not ok then
            RARELOAD.Log("commands"):error("Development reload failed: %s", tostring(err))
            return reply("Reload failed; check the server log.")
        end
        RARELOAD.Net.Push(nil, "dev.reload", {})
        reply("Reloaded.")
    end,
})

Cmd.Register("dev reset", {
    priv = "rareload_admin",
    help = "Cancel restores in progress and write pending data to disk",
    fn = function(_, _, reply)
        for _, other in player.Iterator() do RARELOAD.Pipeline.Cancel(other) end
        RARELOAD.Store.Flush()
        reply("Reset done.")
    end,
})
