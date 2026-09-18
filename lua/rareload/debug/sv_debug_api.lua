-- Rareload debug API surface, implemented on the v2 engine (sv_debug_core).
-- Everything the rest of the addon calls resolves to Debug.Log / Debug.Session,
-- so the old 8-file system can be deleted with the call sites untouched.
if not SERVER then return end

RARELOAD = RARELOAD or {}
local Debug = RARELOAD.Debug
if not Debug then return end

--------------------------------------------------------------------------------
-- Write: legacy (category, level, indent, message, context) -> structured Log.
-- The manual indent and context.entity are no longer needed (per-player scoping
-- and grouping are handled by the engine), so they are dropped.
--------------------------------------------------------------------------------
function Debug.Write(category, level, _indent, message, _context)
    return Debug.Log(category, level, message)
end

-- Legacy grouped log: a title plus a list (or single) of detail lines.
function Debug.LogGroup(title, level, lines, category, _ply)
    local data
    if istable(lines) then data = lines
    elseif lines ~= nil then data = { tostring(lines) } end
    return Debug.Log(category or "system", level, title, data)
end

-- Legacy alias: message straight to one player.
Debug.SendToPlayer = Debug.ToPlayer

-- Legacy alias: Formatters -> Fmt.
Debug.Formatters = Debug.Fmt

--------------------------------------------------------------------------------
-- Anti-stuck logging
--------------------------------------------------------------------------------
local function inferLevel(text, given)
    if given then return given end
    text = string.lower(tostring(text or ""))
    if text:find("error") or text:find("fail") or text:find("critical") then return "ERROR" end
    if text:find("warn") or text:find("invalid") then return "WARN" end
    return "INFO"
end

-- Debug.AntiStuck(header, messages, entity, level): header plus optional data.
function Debug.AntiStuck(header, messages, _entity, level)
    local data = istable(messages) and messages or nil
    local msg = header
    if not data and messages ~= nil and messages ~= "" then
        msg = tostring(header) .. ": " .. tostring(messages)
    end
    return Debug.Log("anti_stuck", inferLevel(header, level), msg, data)
end

function Debug.LogAntiStuckResult(ply, originalPos, finalPos, method, success)
    if not IsValid(ply) then return end
    Debug.Log("anti_stuck", success and "INFO" or "WARN", "Anti-Stuck Resolution", {
        original = Debug.Fmt.Vector(originalPos),
        final = Debug.Fmt.Vector(finalPos),
        method = method or "Unknown",
        success = success and "Yes" or "No",
        moved = (isvector(originalPos) and isvector(finalPos))
            and string.format("%.1f units", originalPos:Distance(finalPos)) or nil,
    })
end

function Debug.LogAntiStuckOperation(operation, methodName, data, _ply)
    local header = "Anti-Stuck" .. ((methodName and methodName ~= "") and (" [" .. methodName .. "]") or "")
    local out = { operation = tostring(operation) }
    if istable(data) then
        for k, v in pairs(data) do
            if type(v) ~= "table" then out[k] = tostring(v) end
        end
        if istable(data.methods) then
            for i, m in ipairs(data.methods) do
                out["method_" .. i] = string.format("%s (%s)", tostring(m.name), m.enabled and "on" or "off")
            end
        end
    end
    Debug.Log("anti_stuck", inferLevel(operation), header, out)
end

-- Old dispatcher kept for the two call shapes it served.
function Debug.LogAntiStuck(ply, originalPos, finalPos, method, success)
    if IsValid(ply) and originalPos and isvector(originalPos) then
        return Debug.LogAntiStuckResult(ply, originalPos, finalPos, method, success)
    end
    return Debug.LogAntiStuckOperation(ply, originalPos, finalPos, method)
end

-- Session-style anti-stuck tracking (drives the anti-stuck report card).
function Debug.StartAntiStuckSession(ply, originalPos)
    local sess = Debug.Session("anti_stuck", { ply = ply, title = "Anti-stuck", originalPos = originalPos })
    if sess then
        sess:step("start", "Resolving stuck spawn",
            IsValid(ply) and ply:Nick() or "player")
    end
    return sess
end

function Debug.AntiStuckStep(session, status, title, details)
    if session and session.step then session:step(status, title, details) end
end

function Debug.FinishAntiStuckSession(session, outcome)
    if session and session.finish then session:finish(outcome) end
end

--------------------------------------------------------------------------------
-- Weapon give/skip summary (replaces the old string-building LogWeaponMessages).
--------------------------------------------------------------------------------
function Debug.LogWeaponMessages(debugMessages, debugFlags)
    RARELOAD._weaponLogCooldown = RARELOAD._weaponLogCooldown or 0
    if CurTime() - RARELOAD._weaponLogCooldown < 2.0 then return end

    local any = false
    for _, flag in pairs(debugFlags or {}) do
        if flag then any = true break end
    end
    if not any then return end
    RARELOAD._weaponLogCooldown = CurTime()

    debugMessages = debugMessages or {}
    local data = {}
    local given = debugMessages.givenWeapons or {}
    local ok, fail = 0, 0
    for _, m in ipairs(given) do
        if string.find(m, "^Successfully") then ok = ok + 1
        elseif string.find(m, "^Failed") then fail = fail + 1 end
    end
    if #given > 0 then data.given = string.format("%d ok, %d failed", ok, fail) end
    if debugMessages.adminOnly and #debugMessages.adminOnly > 0 then
        data.adminOnly = #debugMessages.adminOnly
    end
    if debugMessages.skipped and #debugMessages.skipped > 0 then
        data.skipped = #debugMessages.skipped
    end
    Debug.Log("inventory", fail > 0 and "WARN" or "INFO", "Weapon restore", data)
end

--------------------------------------------------------------------------------
-- Weapon clip restore buffer
--------------------------------------------------------------------------------
local clipBuffer = {}
function Debug.BufferClipRestore(clip1, clip2, weapon)
    if not Debug.AnyoneListening() then return end
    clipBuffer[#clipBuffer + 1] = {
        class = IsValid(weapon) and weapon:GetClass() or "Unknown",
        c1 = (clip1 and clip1 >= 0) and clip1 or "N/A",
        c2 = (clip2 and clip2 >= 0) and clip2 or "N/A",
    }
end

function Debug.FlushClipRestoreBuffer()
    if #clipBuffer == 0 then return end
    local data = {}
    for _, c in ipairs(clipBuffer) do
        data[c.class] = string.format("clip1 %s, clip2 %s", tostring(c.c1), tostring(c.c2))
    end
    Debug.Log("inventory", "INFO", string.format("Restored clips for %d weapons", #clipBuffer), data)
    clipBuffer = {}
end

--------------------------------------------------------------------------------
-- Position save summary (replaces the old diff-tracking SavePosDataInfo).
--------------------------------------------------------------------------------
function Debug.SavePosDataInfo(ply, _oldPosData, playerData)
    if not Debug.AnyoneListening() then return end
    timer.Simple(0.8, function()
        if not IsValid(ply) then return end
        if not playerData then
            Debug.Log("position_save", "ERROR", "Position Save", { error = "missing player data" })
            return
        end
        Debug.Log("position_save", "INFO", "Position Save", {
            map = game.GetMap(),
            player = Debug.Fmt.Player(ply),
            autosave = (RARELOAD.settings and RARELOAD.settings.autoSaveEnabled) and "on" or "off",
        })
    end)
end
