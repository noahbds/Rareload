util.AddNetworkString("RareloadDebugMessage")

function TableToString(tbl, indent)
    if not tbl then return "nil" end

    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    local result = {}

    for k, v in pairs(tbl) do
        local key = tostring(k)
        if type(v) == "table" then
            table.insert(result, indent_str .. key .. " = {")
            table.insert(result, TableToString(v, indent + 1))
            table.insert(result, indent_str .. "}")
        else
            table.insert(result, indent_str .. key .. " = " .. tostring(v))
        end
    end

    return table.concat(result, "\n")
end

local function WriteUtilityDebug(category, level, header, messages, context, entityFallback)
    if RARELOAD.Debug and RARELOAD.Debug.Write then
        RARELOAD.Debug.Write(category or "system", level or "INFO", 0, tostring(header), context)

        if istable(messages) then
            local hadSequential = false
            for _, message in ipairs(messages) do
                hadSequential = true
                RARELOAD.Debug.Write(category or "system", level or "INFO", 1, tostring(message), context)
            end

            if not hadSequential then
                for key, value in pairs(messages) do
                    RARELOAD.Debug.Write(category or "system", level or "INFO", 1,
                        tostring(key) .. " = " .. tostring(value), context)
                end
            end
        elseif messages ~= nil and messages ~= "" then
            RARELOAD.Debug.Write(category or "system", level or "INFO", 1, tostring(messages), context)
        end

        return
    end

    print("[RARELOAD DEBUG] " .. tostring(header))
    if istable(messages) then
        for _, message in ipairs(messages) do
            print("[RARELOAD DEBUG] " .. tostring(message))
        end
    elseif messages ~= nil and messages ~= "" then
        print("[RARELOAD DEBUG] " .. tostring(messages))
    end
end

function RARELOAD.Debug.AntiStuck(header, messages, entity, logLevel)
    if not (DEBUG_CONFIG and DEBUG_CONFIG.ENABLED and DEBUG_CONFIG.ENABLED({ entity = entity })) then return end
    if RARELOAD.Debug.LogAntiStuck then
        local methodName = nil
        if type(messages) == "table" and messages.methodName then
            methodName = messages.methodName
        end
        RARELOAD.Debug.LogAntiStuck(header, methodName, messages or {}, entity)
        return
    end
    local level = logLevel or "INFO"
    if not logLevel then
        if string.find(string.lower(tostring(header)), "error") then
            level = "ERROR"
        elseif string.find(string.lower(tostring(header)), "fail") or
            string.find(string.lower(tostring(header)), "invalid") or
            string.find(string.lower(tostring(header)), "warning") then
            level = "WARNING"
        end
    end
    local formattedHeader = "Anti-Stuck: " .. header
    local context = IsValid(entity) and { entity = entity } or nil
    WriteUtilityDebug("anti_stuck", level, formattedHeader, messages or "", context, entity)
end

function RARELOAD.Debug.SendToPlayer(ply, msg)
    if IsValid(ply) and ply:IsPlayer() then
        net.Start("RareloadDebugMessage")
        net.WriteString(msg)
        net.Send(ply)

        -- On dedicated servers there is no local client console, so keep a server copy.
        if game.IsDedicated() then
            print(msg)
        end
        return
    end

    print(msg)
end
