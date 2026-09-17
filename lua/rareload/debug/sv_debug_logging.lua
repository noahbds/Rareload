function RARELOAD.Debug.Write(category, level, indentLevel, message, context)
    context = context or {}
    if not DEBUG_CONFIG.ENABLED(context) then return end

    category = category or "system"
    level = level or DEBUG_CONFIG.DEFAULT_LEVEL
    indentLevel = indentLevel or 0

    local moduleKey = category:lower()
    local messageKey = tostring(message):sub(1, 50) -- Use first 50 chars as key
    local shouldLog, nextLogTime = DEBUG_CONFIG.CheckRateLimit(moduleKey, messageKey)

    if not shouldLog then
        return
    end

    local categoryDisplay = DEBUG_CONFIG.ModuleCategories[moduleKey] or category:upper()
    local timestamp = DEBUG_CONFIG.GetTimestamp("%H:%M:%S")
    local indent = string.rep("  ", indentLevel)
    local levelConfig = DEBUG_CONFIG.LEVELS[level] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]
    local header = string.format("[%s][%s][%s] %s", timestamp, categoryDisplay, levelConfig.prefix, message)

    if DEBUG_CONFIG.LOG_TO_CONSOLE then
        if indentLevel == 0 then
            MsgC(levelConfig.color, "\n[" .. string.rep("=", 61) .. "]\n")
        end

        MsgC(levelConfig.color, indent .. header)

        if context.entity and IsValid(context.entity) then
            if context.entity:IsPlayer() then
                MsgC(Color(200, 200, 200),
                    " | Player: " .. context.entity:Nick() .. " (" .. context.entity:SteamID() .. ")")
            else
                MsgC(Color(200, 200, 200),
                    " | Entity: " .. context.entity:GetClass() .. " [" .. context.entity:EntIndex() .. "]")
            end
        end

        print("")

        if indentLevel == 0 then
            MsgC(levelConfig.color, "[" .. string.rep("=", 61) .. "]\n")
        end
    end

    if DEBUG_CONFIG.LOG_TO_FILE then
        local fileEntry = indent .. header
        if context.entity and IsValid(context.entity) then
            if context.entity:IsPlayer() then
                fileEntry = fileEntry ..
                    " | Player: " .. context.entity:Nick() .. " (" .. context.entity:SteamID() .. ")"
            else
                fileEntry = fileEntry ..
                    " | Entity: " .. context.entity:GetClass() .. " [" .. context.entity:EntIndex() .. "]"
            end
        end

        DEBUG_CONFIG.AddToLogBuffer(level, categoryDisplay, fileEntry)
    end

    if context.entity and IsValid(context.entity) and context.entity:IsPlayer() and RARELOAD.Debug and RARELOAD.Debug.SendToPlayer then
        local playerLine = indent .. header
        RARELOAD.Debug.SendToPlayer(context.entity, playerLine)
    end
end
