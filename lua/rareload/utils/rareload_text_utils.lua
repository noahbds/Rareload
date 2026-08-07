RARELOAD = RARELOAD or {}
RARELOAD.TextUtils = RARELOAD.TextUtils or {}

local TextUtils = RARELOAD.TextUtils

--[[
    RARELOAD Text & Data Formatting Utilities
    Centralized helper functions for text transformation, boolean formatting,
    and table entry counting.
--]]

-- Converts boolean/nil values to "Yes"/"No" display strings (or nil if input is nil)
function TextUtils.BoolToYesNo(value)
    if value == nil then return nil end
    return value and "Yes" or "No"
end

-- Safely counts entries in a table (returns 0 for non-table/nil inputs)
function TextUtils.CountEntries(tbl)
    if type(tbl) ~= "table" then return 0 end
    if table.Count then return table.Count(tbl) end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Formats entity/NPC/weapon class names cleanly (e.g. "weapon_smg1" -> "Smg1", "npc_citizen" -> "Citizen")
function TextUtils.CompactClassName(className)
    local value = tostring(className or "")
    value = value:gsub("weapon_", ""):gsub("npc_", ""):gsub("_", " ")
    value = value:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest
    end)
    return value
end

-- Formats weapon class names specifically (e.g. "weapon_physcannon" -> "physcannon")
function TextUtils.CompactWeaponClassName(className)
    local value = tostring(className or "")
    value = value:gsub("weapon_", ""):gsub("_", " ")
    return value
end

-- Humanizes camelCase or snake_case key labels into clean title text (e.g. "canOpenDoors" -> "Can Open Doors")
function TextUtils.HumanizeKeyLabel(label)
    local text = tostring(label or "")
    if text == "" then return "" end

    text = text:gsub("_", " ")
    text = text:gsub("(%l)(%u)", "%1 %2")
    text = text:gsub("(%u)(%u%l)", "%1 %2")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

return TextUtils
