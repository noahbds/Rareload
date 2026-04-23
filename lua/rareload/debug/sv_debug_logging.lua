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

local debugSections = {}
local nextSectionId = 1

function RARELOAD.Debug.StartSection(title, category)
    if not DEBUG_CONFIG.ENABLED() then return nil end

    category = category or "system"
    local sectionId = nextSectionId
    nextSectionId = nextSectionId + 1

    local levelConfig = DEBUG_CONFIG.LEVELS["INFO"] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]
    local timestamp = DEBUG_CONFIG.GetTimestamp("%H:%M:%S")
    local categoryDisplay = DEBUG_CONFIG.ModuleCategories[category:lower()] or category:upper()

    debugSections[sectionId] = {
        title = title,
        category = category,
        startTime = SysTime(),
        indent = 0,
        entries = {},
        color = levelConfig.color
    }

    if DEBUG_CONFIG.LOG_TO_CONSOLE then
        MsgC(levelConfig.color, "\n[" .. string.rep("=", 61) .. "]\n")
        MsgC(levelConfig.color, string.format("[%s][%s] %s\n", timestamp, categoryDisplay, title))
    end

    return sectionId
end

function RARELOAD.Debug.AddToSection(sectionId, level, message, indent)
    if not DEBUG_CONFIG.ENABLED() or not debugSections[sectionId] then return end

    indent = indent or 1
    local section = debugSections[sectionId]
    local levelConfig = DEBUG_CONFIG.LEVELS[level] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]
    local timestamp = DEBUG_CONFIG.GetTimestamp("%H:%M:%S")

    local indentStr = string.rep("  ", indent)

    local entry = {
        timestamp = timestamp,
        level = level,
        message = message,
        indent = indentStr
    }
    table.insert(section.entries, entry)

    if DEBUG_CONFIG.LOG_TO_CONSOLE then
        MsgC(levelConfig.color, indentStr .. "[" .. timestamp .. "][" .. levelConfig.prefix .. "] " .. message .. "\n")
    end
end

function RARELOAD.Debug.EndSection(sectionId)
    if not DEBUG_CONFIG.ENABLED() or not debugSections[sectionId] then return 0 end

    local section = debugSections[sectionId]
    local elapsed = SysTime() - section.startTime
    local levelConfig = DEBUG_CONFIG.LEVELS["INFO"] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]

    if DEBUG_CONFIG.LOG_TO_FILE then
        for _, entry in ipairs(section.entries) do
            DEBUG_CONFIG.AddToLogBuffer(entry.level, section.category, entry.indent .. entry.message)
        end
    end

    if DEBUG_CONFIG.LOG_TO_CONSOLE then
        MsgC(levelConfig.color, string.format("[Section completed in %.3fs]\n", elapsed))
        MsgC(levelConfig.color, "[" .. string.rep("=", 61) .. "]\n\n")
    end

    debugSections[sectionId] = nil
    return elapsed
end
