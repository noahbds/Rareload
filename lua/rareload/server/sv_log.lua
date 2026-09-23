-- Logging and report cards (REWRITE_PLAN.md §22). Warnings and errors always reach the console;
-- info and verbose only while the `debug` setting is on. Report cards also go to players with
-- `rareload_debug`.

local LEVELS = { error = 1, warn = 2, info = 3, verbose = 4 }
local COLORS = {
    error = Color(255, 90, 90), warn = Color(255, 200, 80),
    info = Color(120, 200, 255), verbose = Color(160, 160, 160),
}

local function shouldPrint(level)
    return LEVELS[level] <= LEVELS.warn or RARELOAD.Get(nil, "debug")
end

local Logger = {}
Logger.__index = Logger

-- The last RING_SIZE printed events, for `rareload debug recent` (§22).
local RING_SIZE = 500
RARELOAD.LogRing = RARELOAD.LogRing or { events = {}, next = 1, counts = { error = 0, warn = 0 } }
local ring = RARELOAD.LogRing

local function remember(level, category, text)
    ring.events[ring.next] = { t = os.time(), level = level, category = category, text = text }
    ring.next = ring.next % RING_SIZE + 1
    if ring.counts[level] then ring.counts[level] = ring.counts[level] + 1 end
end

-- The `n` newest events, oldest first.
function RARELOAD.LogRecent(n)
    local out = {}
    for i = 1, RING_SIZE do
        local e = ring.events[(ring.next - 1 - i) % RING_SIZE + 1]
        if not e or #out >= n then break end
        table.insert(out, 1, e)
    end
    return out
end

function RARELOAD.LogClear()
    ring.events, ring.next, ring.counts = {}, 1, { error = 0, warn = 0 }
end

for level in pairs(LEVELS) do
    -- The message is only formatted when it will actually be printed.
    Logger[level] = function(self, fmt, ...)
        if not shouldPrint(level) then return end
        local text = string.format(fmt, ...)
        remember(level, self.category, text)
        MsgC(COLORS[level], "[Rareload:" .. self.category .. "] ", color_white, text .. "\n")
    end
end

RARELOAD.Log = setmetatable({}, {
    __call = function(_, category)
        return setmetatable({ category = category }, Logger)
    end,
})

local Session = {}
Session.__index = Session

function Session:step(status, title, detail)
    self.steps[#self.steps + 1] = { status = status, title = title, detail = detail or "" }
end

function Session:finish()
    if not RARELOAD.Get(nil, "debug") then return end
    local ms = math.Round((SysTime() - self.started) * 1000, 1)
    local who = IsValid(self.ply) and self.ply:Nick() or "?"

    MsgC(COLORS.info, "[Rareload] ", color_white, string.format("%s: %s (%s ms)\n", self.title, who, ms))
    for _, s in ipairs(self.steps) do
        MsgC(COLORS[s.status == "ok" and "verbose" or s.status == "warn" and "warn" or "error"],
            "    " .. s.status .. " ", color_white, s.title .. "  " .. s.detail .. "\n")
    end

    -- The listen-server host already sees the server console above.
    local admins = {}
    for _, ply in player.Iterator() do
        if RARELOAD.Can(ply, "rareload_debug") and not ply:IsListenServerHost() then admins[#admins + 1] = ply end
    end
    local ok = true
    for _, s in ipairs(self.steps) do
        if s.status == "fail" then ok = false end
    end
    remember(ok and "info" or "warn", self.kind, string.format("%s: %s (%s ms)", self.title, who, ms))
    if #admins > 0 then
        RARELOAD.Net.Push(admins, "debug", { title = self.title, player = who, ms = ms, steps = self.steps,
            kind = self.kind, ok = ok })
    end
end

-- A grouped record of one save or restore (`kind` = "save" | "restore"); printed as a report card
-- when finished.
function RARELOAD.Log.Session(title, ply, kind)
    return setmetatable({ title = title, ply = ply, kind = kind, steps = {}, started = SysTime() }, Session)
end
