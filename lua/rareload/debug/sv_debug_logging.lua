-- Legacy Log function - DEPRECATED, redirect to Write() for new code
-- This function is kept for backward compatibility with old code

function RARELOAD.Debug.Log(level, header, messages, entity)
    -- DEPRECATED: Use RARELOAD.Debug.Write() for new code
    -- This redirects old calls to the new gateway system
    local debugContext = { entity = entity }
    if not DEBUG_CONFIG.ENABLED(debugContext) then return end

    level = level or DEBUG_CONFIG.DEFAULT_LEVEL
    header = header or ""
    messages = type(messages) == "table" and messages or { messages }

    -- Concatenate table messages for new system
    local message = table.concat(messages, " ")
    local category = "legacy" -- Mark as legacy

    RARELOAD.Debug.Write(category, level, 0, header .. ": " .. message, { entity = entity })
end

-- REMOVED: LogSquadFileOnly() - use Write() with category="squad" for file-only logging
-- Old implementation is superseded by session-based file rotation system

-- DEPRECATED: LogGroup() - use StartSection()/AddToSection()/EndSection() instead
function RARELOAD.Debug.LogGroup(title, level, logEntries)
    if not DEBUG_CONFIG.ENABLED() then return end

    -- Redirect to new hierarchical system
    local sectionId = RARELOAD.Debug.StartSection(title, "system")
    level = level or DEBUG_CONFIG.DEFAULT_LEVEL

    if type(logEntries) == "table" then
        for i, entry in ipairs(logEntries) do
            RARELOAD.Debug.AddToSection(sectionId, level, tostring(entry), 1)
        end
    else
        RARELOAD.Debug.AddToSection(sectionId, level, tostring(logEntries), 1)
    end

    RARELOAD.Debug.EndSection(sectionId)
end

-- Unified logging gateway function
-- All output should route through this function for consistent formatting and rate limiting
-- @param category (string) - Module category (e.g., "anti_stuck", "respawn", "commands")
-- @param level (string) - Log level ("ERROR", "WARNING", "INFO", "VERBOSE")
-- @param indentLevel (number) - Hierarchical indent level (0 = root, 1+ = nested)
-- @param message (string/table) - Message content
-- @param context (table) - Optional context { entity, player, extraInfo }
function RARELOAD.Debug.Write(category, level, indentLevel, message, context)
    context = context or {}
    if not DEBUG_CONFIG.ENABLED(context) then return end

    category = category or "system"
    level = level or DEBUG_CONFIG.DEFAULT_LEVEL
    indentLevel = indentLevel or 0

    -- Check rate limiting
    local moduleKey = category:lower()
    local messageKey = tostring(message):sub(1, 50) -- Use first 50 chars as key
    local shouldLog, nextLogTime = DEBUG_CONFIG.CheckRateLimit(moduleKey, messageKey)

    if not shouldLog then
        -- Silently skip (could log to separate rate-limit file if needed)
        return
    end

    -- Get category display name
    local categoryDisplay = DEBUG_CONFIG.ModuleCategories[moduleKey] or category:upper()

    -- Generate timestamp in console format
    local timestamp = DEBUG_CONFIG.GetTimestamp("%H:%M:%S")

    -- Generate indentation string
    local indent = string.rep("  ", indentLevel)

    -- Format level config
    local levelConfig = DEBUG_CONFIG.LEVELS[level] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]

    -- Build header
    local header = string.format("[%s][%s][%s] %s", timestamp, categoryDisplay, levelConfig.prefix, message)

    -- Console output with hierarchical indentation
    if DEBUG_CONFIG.LOG_TO_CONSOLE then
        if indentLevel == 0 then
            -- Root level: show separator
            MsgC(levelConfig.color, "\n[" .. string.rep("=", 61) .. "]\n")
        end

        MsgC(levelConfig.color, indent .. header)

        -- Add context if provided
        if context.entity and IsValid(context.entity) then
            if context.entity:IsPlayer() then
                MsgC(Color(200, 200, 200),
                    " | Player: " .. context.entity:Nick() .. " (" .. context.entity:SteamID() .. ")")
            else
                MsgC(Color(200, 200, 200),
                    " | Entity: " .. context.entity:GetClass() .. " [" .. context.entity:EntIndex() .. "]")
            end
        end

        print("") -- Newline

        if indentLevel == 0 then
            MsgC(levelConfig.color, "[" .. string.rep("=", 61) .. "]\n")
        end
    end

    -- File output
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

        -- Add to buffer with category for session-based file rotation
        DEBUG_CONFIG.AddToLogBuffer(level, categoryDisplay, fileEntry)
    end
end

-- Hierarchical section management for structured output
local debugSections = {} -- { id => { title, category, startTime, indent, color } }
local nextSectionId = 1

-- Start a new debug section
-- @param title (string) - Section title
-- @param category (string) - Module category (for rate limiting and formatting)
-- @return sectionId (number) - Unique section identifier for use in AddToSection/EndSection
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

-- Add a message to an open section (with indentation)
-- @param sectionId (number) - Section identifier from StartSection()
-- @param level (string) - Log level
-- @param message (string) - Message content
-- @param indent (number) - Optional indent level relative to section (defaults to 1)
function RARELOAD.Debug.AddToSection(sectionId, level, message, indent)
    if not DEBUG_CONFIG.ENABLED() or not debugSections[sectionId] then return end

    indent = indent or 1
    local section = debugSections[sectionId]
    local levelConfig = DEBUG_CONFIG.LEVELS[level] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]
    local timestamp = DEBUG_CONFIG.GetTimestamp("%H:%M:%S")

    -- Generate indentation (2 spaces per level, starting from 1)
    local indentStr = string.rep("  ", indent)

    -- Format and store entry
    local entry = {
        timestamp = timestamp,
        level = level,
        message = message,
        indent = indentStr
    }
    table.insert(section.entries, entry)

    -- Console output
    if DEBUG_CONFIG.LOG_TO_CONSOLE then
        MsgC(levelConfig.color, indentStr .. "[" .. timestamp .. "][" .. levelConfig.prefix .. "] " .. message .. "\n")
    end
end

-- Finish and close a debug section
-- @param sectionId (number) - Section identifier from StartSection()
-- @return elapsed (number) - Time elapsed since StartSection() in seconds
function RARELOAD.Debug.EndSection(sectionId)
    if not DEBUG_CONFIG.ENABLED() or not debugSections[sectionId] then return 0 end

    local section = debugSections[sectionId]
    local elapsed = SysTime() - section.startTime
    local levelConfig = DEBUG_CONFIG.LEVELS["INFO"] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]

    -- Log file output
    if DEBUG_CONFIG.LOG_TO_FILE then
        for _, entry in ipairs(section.entries) do
            DEBUG_CONFIG.AddToLogBuffer(entry.level, section.category, entry.indent .. entry.message)
        end
    end

    -- Console closing
    if DEBUG_CONFIG.LOG_TO_CONSOLE then
        MsgC(levelConfig.color, string.format("[Section completed in %.3fs]\n", elapsed))
        MsgC(levelConfig.color, "[" .. string.rep("=", 61) .. "]\n\n")
    end

    debugSections[sectionId] = nil
    return elapsed
end
