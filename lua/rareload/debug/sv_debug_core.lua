-- Rareload debug engine (v2): structured, per-player, in-memory.
-- Replaces the old file-logging stack. One namespace, one Log() entry point,
-- an in-memory ring buffer, correct per-player scoping, and grouped Sessions.
if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.Debug = RARELOAD.Debug or {}
local Debug = RARELOAD.Debug

--------------------------------------------------------------------------------
-- Levels
--------------------------------------------------------------------------------
Debug.LEVELS = {
    ERROR   = { n = 1, label = "ERROR",   color = Color(255, 80, 80) },
    WARN    = { n = 2, label = "WARN",    color = Color(255, 175, 60) },
    INFO    = { n = 3, label = "INFO",    color = Color(90, 180, 255) },
    VERBOSE = { n = 4, label = "VERBOSE", color = Color(165, 165, 165) },
}
local LEVEL_ALIAS = { WARNING = "WARN", DEBUG = "VERBOSE", TRACE = "VERBOSE",
    [1] = "ERROR", [2] = "WARN", [3] = "INFO", [4] = "VERBOSE" }

local function resolveLevel(level)
    if type(level) == "number" then level = LEVEL_ALIAS[level] end
    if type(level) == "string" then
        local up = level:upper()
        return Debug.LEVELS[up] or Debug.LEVELS[LEVEL_ALIAS[up] or ""] or Debug.LEVELS.INFO
    end
    return Debug.LEVELS.INFO
end
Debug.ResolveLevel = resolveLevel

--------------------------------------------------------------------------------
-- Enablement (per-player, correctly scoped)
--------------------------------------------------------------------------------
function Debug.GlobalEnabled()
    return RARELOAD.settings and RARELOAD.settings.debugEnabled == true
end

function Debug.MinLevel()
    local name = (RARELOAD.settings and RARELOAD.settings.debugLevel) or "INFO"
    return resolveLevel(name).n
end

-- True if THIS player has debug on (or the global switch is on). Unlike the old
-- system this does NOT return true just because some other player enabled it.
function Debug.EnabledFor(ply)
    if Debug.GlobalEnabled() then return true end
    if IsValid(ply) and RARELOAD.GetPlayerSetting then
        return RARELOAD.GetPlayerSetting(ply, "debugEnabled", false) == true
    end
    return false
end

-- Players who should receive streamed events.
function Debug.Subscribers()
    local subs = {}
    if not player or not player.GetHumans then return subs end
    local global = Debug.GlobalEnabled()
    for _, ply in ipairs(player.GetHumans()) do
        if global or Debug.EnabledFor(ply) then subs[#subs + 1] = ply end
    end
    return subs
end

local function anyoneListening()
    if Debug.GlobalEnabled() then return true end
    return #Debug.Subscribers() > 0
end
Debug.AnyoneListening = anyoneListening

--------------------------------------------------------------------------------
-- Formatters (pure display helpers; replaces Debug.Formatters)
--------------------------------------------------------------------------------
Debug.Fmt = Debug.Fmt or {}
function Debug.Fmt.Vector(v)
    if RARELOAD.DataUtils and RARELOAD.DataUtils.FormatVectorCompact then
        return RARELOAD.DataUtils.FormatVectorCompact(v)
    end
    if not v then return "nil" end
    return string.format("[%.1f %.1f %.1f]", v.x or 0, v.y or 0, v.z or 0)
end
function Debug.Fmt.Angle(a)
    if RARELOAD.DataUtils and RARELOAD.DataUtils.FormatAngleCompact then
        return RARELOAD.DataUtils.FormatAngleCompact(a)
    end
    if not a then return "nil" end
    return string.format("[%.1f %.1f %.1f]", a.p or a.pitch or 0, a.y or a.yaw or 0, a.r or a.roll or 0)
end
function Debug.Fmt.Player(ply)
    if not IsValid(ply) then return "Invalid Player" end
    return string.format("%s (%s)", ply:Nick(), ply:SteamID())
end
function Debug.Fmt.Entity(ent)
    if not IsValid(ent) then return "Invalid Entity" end
    return string.format("%s [%d]", ent:GetClass(), ent:EntIndex())
end
function Debug.Fmt.Table(tbl, maxDepth)
    maxDepth = maxDepth or 2
    if type(tbl) ~= "table" then return tostring(tbl) end
    local function rec(t, depth)
        if depth > maxDepth then return "{...}" end
        local parts = {}
        for k, v in pairs(t) do
            local vs
            if type(v) == "table" then
                vs = rec(v, depth + 1)
            elseif isvector(v) then
                vs = Debug.Fmt.Vector(v)
            elseif isangle(v) then
                vs = Debug.Fmt.Angle(v)
            else
                vs = tostring(v)
            end
            parts[#parts + 1] = tostring(k) .. " = " .. vs
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return rec(tbl, 1)
end

-- Turn an arbitrary value into a short display string for a data field.
local function stringifyValue(v)
    if v == nil then return "nil" end
    local t = TypeID and TypeID(v)
    if isvector(v) then return Debug.Fmt.Vector(v) end
    if isangle(v) then return Debug.Fmt.Angle(v) end
    if IsColor and IsColor(v) then return string.format("%d,%d,%d", v.r, v.g, v.b) end
    if type(v) == "table" then return Debug.Fmt.Table(v) end
    if IsEntity and isentity and isentity(v) then
        if not IsValid(v) then return "NULL" end
        return v:IsPlayer() and Debug.Fmt.Player(v) or Debug.Fmt.Entity(v)
    end
    return tostring(v)
end

-- Normalize a data table to an ordered list of {key, value} string pairs so the
-- HUD renders deterministically. Array-like tables keep their order.
local function sanitizeData(data)
    if type(data) ~= "table" then return nil end
    local pairsOut = {}
    local seen = {}
    for i = 1, #data do
        if data[i] ~= nil then
            seen[i] = true
            pairsOut[#pairsOut + 1] = { "", stringifyValue(data[i]) }
        end
    end
    for k, v in pairs(data) do
        if not seen[k] then
            pairsOut[#pairsOut + 1] = { tostring(k), stringifyValue(v) }
        end
    end
    if #pairsOut == 0 then return nil end
    return pairsOut
end
Debug.SanitizeData = sanitizeData

--------------------------------------------------------------------------------
-- Ring buffer
--------------------------------------------------------------------------------
Debug.RING_MAX = 500
local ring = {}
local ringHead = 0
Debug.ring = ring

function Debug.ClearRing()
    for i = 1, #ring do ring[i] = nil end
    ringHead = 0
end

-- Recent events, oldest first.
function Debug.Recent(count)
    count = math.min(count or Debug.RING_MAX, Debug.RING_MAX, ringHead)
    local out = {}
    for i = ringHead - count + 1, ringHead do
        out[#out + 1] = ring[((i - 1) % Debug.RING_MAX) + 1]
    end
    return out
end

--------------------------------------------------------------------------------
-- Console output
--------------------------------------------------------------------------------
local WHITE = Color(220, 220, 220)
local DIM = Color(140, 140, 140)
local function consoleWrite(ev, lv)
    MsgC(lv.color, string.format("[RARELOAD][%s][%s] ", ev.category:upper(), lv.label))
    MsgC(WHITE, ev.message .. "\n")
    if ev.data then
        for _, kv in ipairs(ev.data) do
            MsgC(DIM, "    " .. (kv[1] ~= "" and (kv[1] .. " = ") or "") .. kv[2] .. "\n")
        end
    end
end

--------------------------------------------------------------------------------
-- Core Log
--------------------------------------------------------------------------------
-- Debug.Log(category, level, message, data)
--   category : string bucket ("respawn", "anti_stuck", "inventory", ...)
--   level    : "ERROR"|"WARN"|"INFO"|"VERBOSE" (or legacy "WARNING"/1..4)
--   message  : string
--   data     : optional table rendered as key/value rows
function Debug.Log(category, level, message, data)
    local lv = resolveLevel(level)
    if lv.n > Debug.MinLevel() then return end
    if not anyoneListening() then return end

    ringHead = ringHead + 1
    local ev = {
        seq = ringHead,
        time = os.time(),
        category = tostring(category or "system"),
        level = lv.n,
        levelName = lv.label,
        message = tostring(message or ""),
        data = sanitizeData(data),
    }
    ring[((ringHead - 1) % Debug.RING_MAX) + 1] = ev

    consoleWrite(ev, lv)
    if Debug.Broadcast then Debug.Broadcast(ev) end
    return ev
end

-- Direct one-liner to a single player (console on dedicated, HUD line client-side).
function Debug.ToPlayer(ply, message)
    message = tostring(message)
    if not IsValid(ply) then print(message); return end
    if game.IsDedicated() then print(message) end
    if Debug.SendTo then
        Debug.SendTo(ply, {
            seq = 0, time = os.time(), category = "direct",
            level = 3, levelName = "INFO", message = message,
        })
    end
end

--------------------------------------------------------------------------------
-- Sessions (grouped, step-by-step; drives the anti-stuck / respawn report views)
--------------------------------------------------------------------------------
local STEP_ICON = { ok = "✓", fail = "✗", start = "⚡", warn = "!" }

-- Debug.Session(category, meta) -> handle
--   handle:step(status, title, dataOrDetail)
--   handle:finish(outcome)   outcome = { success, attempts, totalTime, reason, ... }
function Debug.Session(category, meta)
    meta = meta or {}
    local sess = {
        category = category or "system",
        meta = meta,
        ply = meta.ply,
        steps = {},
        startedAt = SysTime(),
    }

    function sess:step(status, title, dataOrDetail)
        local detail, data
        if type(dataOrDetail) == "string" then
            detail = dataOrDetail
        elseif type(dataOrDetail) == "table" then
            data = dataOrDetail
        end
        local st = {
            status = status,
            title = tostring(title or ""),
            detail = detail,
            data = sanitizeData(data),
            t = SysTime() - self.startedAt,
        }
        self.steps[#self.steps + 1] = st

        local icon = STEP_ICON[status] or "•"
        local line = icon .. " " .. st.title
        if detail and detail ~= "" then line = line .. " — " .. detail end
        Debug.Log(self.category, status == "fail" and "WARN" or "VERBOSE", line, data)
        return self
    end

    function sess:finish(outcome)
        outcome = outcome or {}
        self.outcome = outcome
        self.elapsed = outcome.totalTime or (SysTime() - self.startedAt)
        Debug.Log(self.category, outcome.success and "INFO" or "WARN", "Session complete", {
            result = outcome.success and "SUCCESS" or "FAILURE",
            attempts = outcome.attempts,
            time = string.format("%.3fs", self.elapsed),
            reason = outcome.reason,
        })
        if Debug.SendReport then Debug.SendReport(self) end
        return self
    end

    return sess
end
