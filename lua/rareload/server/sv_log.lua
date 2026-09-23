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

for level in pairs(LEVELS) do
    -- The message is only formatted when it will actually be printed.
    Logger[level] = function(self, fmt, ...)
        if not shouldPrint(level) then return end
        MsgC(COLORS[level], "[Rareload:" .. self.category .. "] ", color_white, string.format(fmt, ...) .. "\n")
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
    if #admins > 0 then
        RARELOAD.Net.Push(admins, "debug", { title = self.title, player = who, ms = ms, steps = self.steps })
    end
end

-- A grouped record of one save or restore; printed as a report card when finished.
function RARELOAD.Log.Session(title, ply)
    return setmetatable({ title = title, ply = ply, steps = {}, started = SysTime() }, Session)
end
