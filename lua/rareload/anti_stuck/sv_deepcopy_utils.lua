local function DeepCopy(original, copies)
    copies = copies or {}
    local originalType = type(original)
    local copy

    if originalType == 'table' then
        if copies[original] then
            return copies[original]
        end
        copy = {}
        copies[original] = copy
        for originalKey, originalValue in next, original, nil do
            copy[DeepCopy(originalKey, copies)] = DeepCopy(originalValue, copies)
        end
        setmetatable(copy, DeepCopy(getmetatable(original), copies))
    else
        copy = original
    end
    return copy
end

local function DeepCopySettings(settings)
    if not settings or type(settings) ~= "table" then
        return {}
    end

    local copy = {}
    for key, value in pairs(settings) do
        if type(value) == "table" then
            copy[key] = DeepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

local function DeepCopyMethods(methods)
    if not methods or type(methods) ~= "table" then
        return {}
    end

    local copy = {}
    for i, method in ipairs(methods) do
        if type(method) == "table" then
            copy[i] = {
                name = method.name,
                func = method.func,
                enabled = method.enabled,
                description = method.description
            }
            for key, value in pairs(method) do
                if key ~= "name" and key ~= "func" and key ~= "enabled" and key ~= "description" then
                    if type(value) == "table" then
                        copy[i][key] = DeepCopy(value)
                    else
                        copy[i][key] = value
                    end
                end
            end
        else
            copy[i] = method
        end
    end
    return copy
end

_G.RareloadDeepCopy = DeepCopy
_G.RareloadDeepCopySettings = DeepCopySettings
_G.RareloadDeepCopyMethods = DeepCopyMethods

print("[RARELOAD] Server-side deep copy utility functions loaded")
