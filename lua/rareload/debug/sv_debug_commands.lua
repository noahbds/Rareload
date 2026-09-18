-- Server-side debug command, mainly for the dedicated-server console / rcon.
-- Players get the richer client-side `rareload_debug` (HUD, filters) instead.
if not SERVER then return end

RARELOAD = RARELOAD or {}
local Debug = RARELOAD.Debug
if not Debug then return end

local function allowed(ply)
    if not IsValid(ply) then return true end -- server console / rcon
    return RARELOAD.Permissions and RARELOAD.Permissions.HasPermission
        and RARELOAD.Permissions.HasPermission(ply, "DEBUG_MENU")
end

local function reply(ply, msg)
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[Rareload] " .. msg) else print("[RARELOAD] " .. msg) end
end

concommand.Add("rareload_debug", function(ply, _, args)
    if not allowed(ply) then return end
    RARELOAD.settings = RARELOAD.settings or {}
    local sub = (args[1] or "toggle"):lower()

    if sub == "toggle" or sub == "on" or sub == "off" then
        if sub == "on" then RARELOAD.settings.debugEnabled = true
        elseif sub == "off" then RARELOAD.settings.debugEnabled = false
        else RARELOAD.settings.debugEnabled = not RARELOAD.settings.debugEnabled end
        reply(ply, "Global debug " .. (RARELOAD.settings.debugEnabled and "enabled" or "disabled"))
    elseif sub == "level" then
        local lvl = args[2] and args[2]:upper()
        if lvl and Debug.LEVELS[lvl] then
            RARELOAD.settings.debugLevel = lvl
            reply(ply, "Debug level set to " .. lvl)
        else
            reply(ply, "Levels: ERROR, WARN, INFO, VERBOSE")
        end
    elseif sub == "dump" then
        local recent = Debug.Recent(tonumber(args[2]) or 40)
        for _, ev in ipairs(recent) do
            print(string.format("[%s][%s] %s", ev.category:upper(), ev.levelName, ev.message))
        end
        reply(ply, "Dumped " .. #recent .. " events")
    elseif sub == "clear" then
        Debug.ClearRing()
        reply(ply, "Debug ring cleared")
    else
        reply(ply, "Usage: rareload_debug [toggle|on|off|level <L>|dump [n]|clear]")
    end
end, nil, "Rareload debug: toggle/level/dump/clear (server console).")
