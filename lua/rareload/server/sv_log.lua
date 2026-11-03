-- Logging and report cards (REWRITE_PLAN.md §22). How much reaches the console is the `logLevel`
-- setting:
--   errors    only errors
--   warnings  errors, and warnings (a part of a save or restore that went wrong, a refused upload…)
--   activity  also one line per save, restore, import, share and admin change (the default)
--   debug     also every step of every save and restore, autosaves, and other details
-- The `debug` setting turns on the debug level too. Every printed line is kept in a ring for
-- `rareload log`, and written to data/rareload/logs/<date>.txt when `logToFile` is on. Report cards
-- still go to players with rareload_debug while the debug setting is on.

local LEVELS = { error = 1, warn = 2, info = 3, verbose = 4 }
local SETTING_LEVEL = { errors = 1, warnings = 2, activity = 3, debug = 4 }
local COLORS = {
    error = Color(255, 90, 90),
    warn = Color(255, 200, 80),
    info = Color(120, 200, 255),
    verbose = Color(160, 160, 160),
}
local MARK = { error = "x", warn = "!", info = " ", verbose = " " }

-- The level printed now: the logLevel setting, raised to debug while the debug setting is on.
local function threshold()
    local level = SETTING_LEVEL[RARELOAD.Get(nil, "logLevel")] or LEVELS.info
    if RARELOAD.Get(nil, "debug") then level = LEVELS.verbose end
    return level
end

function RARELOAD.LogWants(level)
    return LEVELS[level] <= threshold()
end

-- The last RING_SIZE printed events, for `rareload log` (§22).
local RING_SIZE = 1000
RARELOAD.LogRing = RARELOAD.LogRing or { events = {}, next = 1, counts = { error = 0, warn = 0 } }
local ring = RARELOAD.LogRing

-- Log file: one line per event, a file per day, old ones removed at startup.
local function toFile(e)
    if not RARELOAD.Get(nil, "logToFile") then return end
    RARELOAD.Store.AppendLog(os.date("%Y-%m-%d", e.t), string.format("%s %-7s %-10s %s%s",
        os.date("%H:%M:%S", e.t), e.level, e.category, e.sid and ("[" .. e.sid .. "] ") or "", e.text))
end

local function remember(level, category, text, ply)
    local e = { t = os.time(), level = level, category = category, text = text }
    if IsValid(ply) and ply:IsPlayer() then e.nick, e.sid = ply:Nick(), ply:SteamID64() or "?" end
    ring.events[ring.next] = e
    ring.next = ring.next % RING_SIZE + 1
    if ring.counts[level] then ring.counts[level] = ring.counts[level] + 1 end
    toFile(e)
    return e
end

local function echo(level, category, text)
    MsgC(COLORS[level], "[Rareload:" .. category .. "] ", color_white, text .. "\n")
end

-- The `n` newest events matching `filter` (nil for all), oldest first. A filter word is a level
-- (errors, warnings, activity, debug), a category, or text found in the event or the player's name.
local FILTER_LEVELS = { errors = "error", error = "error", warnings = "warn", warning = "warn", warn = "warn",
    activity = "info", info = "info", debug = "verbose", verbose = "verbose" }

function RARELOAD.LogRecent(n, filter)
    local want, words = nil, {}
    for word in string.gmatch(string.lower(filter or ""), "%S+") do
        if FILTER_LEVELS[word] then want = FILTER_LEVELS[word] else words[#words + 1] = word end
    end
    local out = {}
    for i = 1, RING_SIZE do
        local e = ring.events[(ring.next - 1 - i) % RING_SIZE + 1]
        if not e or #out >= n then break end
        local ok = not want or e.level == want or (want == "warn" and e.level == "error")
        for _, word in ipairs(words) do
            local hay = string.lower(e.category .. " " .. e.text .. " " .. (e.nick or "") .. " " .. (e.sid or ""))
            ok = ok and string.find(hay, word, 1, true) ~= nil
        end
        if ok then table.insert(out, 1, e) end
    end
    return out
end

function RARELOAD.LogClear()
    ring.events, ring.next, ring.counts = {}, 1, { error = 0, warn = 0 }
end

-- RARELOAD.Log(category):info(fmt, …), or RARELOAD.Log(category, ply) to tie the lines to a player
-- (shown in the file, and found by `rareload log <name>`).
local Logger = {}
Logger.__index = Logger

for level in pairs(LEVELS) do
    Logger[level] = function(self, fmt, ...)
        if not RARELOAD.LogWants(level) then return end
        local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
        remember(level, self.category, text, self.ply)
        echo(level, self.category, text)
    end
end

RARELOAD.Log = setmetatable({}, {
    __call = function(_, category, ply)
        return setmetatable({ category = category, ply = ply }, Logger)
    end,
})

-- Sessions: one save or restore -----------------------------------------------------------------------

local Session = {}
Session.__index = Session
local cardCount = 0

-- `ms`: how long the step took, when it was timed.
function Session:step(status, title, detail, ms)
    self.steps[#self.steps + 1] = {
        status = status, title = title, detail = detail or "", ms = ms and math.Round(ms, 2)
    }
end

-- What a save holds, in a few words: "34 entities, 2 NPCs, 1 vehicle, 8 weapons".
local function contents(data)
    if not istable(data) then return nil end
    local info = RARELOAD.History.Info(data)
    local parts = {}
    local function add(n, one, many)
        if (tonumber(n) or 0) > 0 then parts[#parts + 1] = n .. " " .. (n == 1 and one or many) end
    end
    add(info.entities, "object", "objects")
    add(info.npcs, "NPC", "NPCs")
    add(info.vehicles, "vehicle", "vehicles")
    add(info.weapons, "weapon", "weapons")
    if data.mapState or data.environment or data.worldSettings then parts[#parts + 1] = "map and weather" end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

-- The one-line summary of a session, e.g.
--   Noah saved No. 12 (tool, 42 ms): 34 objects, 2 NPCs, 8 weapons
--   Restored No. 12 for Noah (spawn, 120 ms): 34 objects, 8 weapons - 1 warning
local function headline(self, info, ms, warns, fails)
    local who = IsValid(self.ply) and self.ply:Nick() or "?"
    local why = info.reason or "?"
    local text
    if self.kind == "save" then
        text = info.result == "unchanged" and string.format("%s saved (%s): nothing changed since No. %s", who, why,
            tostring(info.entry)) or string.format("%s saved No. %s (%s, %s ms)", who, tostring(info.entry), why, ms)
    else
        text = string.format("Restored No. %s for %s (%s, %s ms)", tostring(info.entry or "-"), who, why, ms)
    end
    local what = info.result ~= "unchanged" and contents(info.data)
    if what then text = text .. ": " .. what end
    if fails > 0 then text = text .. string.format(" - %d failed", fails) end
    if warns > 0 then text = text .. string.format(" - %d warning%s", warns, warns == 1 and "" or "s") end
    return text
end

-- info = { entry? (save number), result? ("saved" | "unchanged"), reason?, auto?, data? (the save's
-- data, for the summary) }. Autosaves are only logged at the debug level, unless something went wrong.
function Session:finish(info)
    info = info or {}
    local ms = math.Round((SysTime() - self.started) * 1000, 1)
    local warns, fails = 0, 0
    for _, s in ipairs(self.steps) do
        if s.status == "warn" then warns = warns + 1 elseif s.status == "fail" then fails = fails + 1 end
    end
    local level = fails > 0 and "error" or warns > 0 and "warn" or info.auto and "verbose" or "info"

    if RARELOAD.LogWants(level) then
        local category = self.kind
        local text = headline(self, info, ms, warns, fails)
        remember(level, category, text, self.ply)
        echo(level, category, text)
        -- What went wrong is always shown with it; every step at the debug level.
        local all = RARELOAD.LogWants("verbose")
        for _, s in ipairs(self.steps) do
            if all or s.status ~= "ok" then
                local stepLevel = s.status == "fail" and "error" or s.status == "warn" and "warn" or "verbose"
                local line = string.format("  %s %s: %s%s", MARK[stepLevel], s.title, s.detail,
                    s.ms and string.format(" (%s ms)", s.ms) or "")
                if s.status ~= "ok" then remember(stepLevel, category, line, self.ply) end
                MsgC(COLORS[stepLevel], line .. "\n")
            end
        end
    end

    if not RARELOAD.Get(nil, "debug") then return end
    local admins, host = {}, nil
    for _, ply in player.Iterator() do
        if RARELOAD.Can(ply, "rareload_debug") then
            if ply:IsListenServerHost() then host = ply else admins[#admins + 1] = ply end
        end
    end
    local card = {
        title = self.title,
        player = IsValid(self.ply) and self.ply:Nick() or "?",
        ms = ms,
        steps = self.steps,
        kind = self.kind,
        ok = fails == 0,
        info = { entry = info.entry, result = info.result, reason = info.reason, auto = info.auto },
        map = game.GetMap()
    }
    cardCount = cardCount + 1
    local opts = { key = "debug:" .. cardCount }
    if #admins > 0 then RARELOAD.Net.Push(admins, "debug", card, opts) end
    if host then
        card.quiet = true
        RARELOAD.Net.Push(host, "debug", card, opts)
    end
end

-- A grouped record of one save or restore (`kind` = "save" | "restore"); logged and sent as a report
-- card when finished.
function RARELOAD.Log.Session(title, ply, kind)
    return setmetatable({ title = title, ply = ply, kind = kind, steps = {}, started = SysTime() }, Session)
end
