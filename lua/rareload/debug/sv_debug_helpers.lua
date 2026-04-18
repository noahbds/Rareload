if not SERVER then return {} end

RARELOAD = RARELOAD or {}

if RARELOAD.DebugHelpers and RARELOAD.DebugHelpers.Write then
    return RARELOAD.DebugHelpers
end

local DebugState = include("rareload/debug/sv_debug_state.lua")

local DebugHelpers = RARELOAD.DebugHelpers or {}
RARELOAD.DebugHelpers = DebugHelpers

local function IsGlobalDebugEnabled()
    return RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled == true
end

function DebugHelpers.IsEnabledForPlayer(ply)
    if DebugState and DebugState.IsEnabledForPlayer then
        return DebugState.IsEnabledForPlayer(ply)
    end

    if IsValid(ply) and RARELOAD and RARELOAD.GetPlayerSetting then
        local ok, enabled = pcall(RARELOAD.GetPlayerSetting, ply, "debugEnabled", false)
        if ok then
            return enabled == true
        end
    end

    if DEBUG_CONFIG and DEBUG_CONFIG.ENABLED then
        local ok, enabled = pcall(DEBUG_CONFIG.ENABLED, { entity = ply })
        if ok then
            return enabled == true
        end
    end

    return IsGlobalDebugEnabled()
end

local function WriteDetails(category, logLevel, details, context, detailsAsPairs)
    if not istable(details) then
        if details ~= nil then
            RARELOAD.Debug.Write(category, logLevel, 1, tostring(details), context)
        end
        return
    end

    if detailsAsPairs then
        for key, value in pairs(details) do
            RARELOAD.Debug.Write(category, logLevel, 1, tostring(key) .. ": " .. tostring(value), context)
        end
        return
    end

    local hasSequential = false
    for _, line in ipairs(details) do
        hasSequential = true
        RARELOAD.Debug.Write(category, logLevel, 1, tostring(line), context)
    end

    if hasSequential then
        return
    end

    for key, value in pairs(details) do
        RARELOAD.Debug.Write(category, logLevel, 1, tostring(key) .. ": " .. tostring(value), context)
    end
end

function DebugHelpers.PrintLines(prefix, message, details, detailsAsPairs)
    local linePrefix = prefix or "[RARELOAD DEBUG] "

    print(linePrefix .. tostring(message))

    if not istable(details) then
        if details ~= nil then
            print(linePrefix .. tostring(details))
        end
        return
    end

    if detailsAsPairs then
        for key, value in pairs(details) do
            print(linePrefix .. tostring(key) .. ": " .. tostring(value))
        end
        return
    end

    local hasSequential = false
    for _, line in ipairs(details) do
        hasSequential = true
        print(linePrefix .. tostring(line))
    end

    if hasSequential then
        return
    end

    for key, value in pairs(details) do
        print(linePrefix .. tostring(key) .. ": " .. tostring(value))
    end
end

function DebugHelpers.Write(category, level, message, details, opts)
    opts = opts or {}

    local ply = opts.ply
    local context = opts.context
    if context == nil and IsValid(ply) then
        context = { entity = ply }
    end

    local gate = opts.gate
    if gate == true then
        if not DebugHelpers.IsEnabledForPlayer(ply) then
            return false
        end
    elseif gate == "any" then
        if not (DebugState and DebugState.IsAnyEnabled and DebugState.IsAnyEnabled()) then
            return false
        end
    elseif isfunction(gate) then
        if not gate(ply, context) then
            return false
        end
    end

    local logLevel = level or "INFO"
    if RARELOAD.Debug and RARELOAD.Debug.Write then
        RARELOAD.Debug.Write(category or "system", logLevel, 0, tostring(message), context)
        WriteDetails(category or "system", logLevel, details, context, opts.detailsAsPairs == true)
        return true
    end

    if opts.allowPrintFallback then
        DebugHelpers.PrintLines(opts.printPrefix, message, details, opts.detailsAsPairs == true)
        return true
    end

    return false
end

return DebugHelpers
