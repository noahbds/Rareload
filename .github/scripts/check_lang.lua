-- Checks that every language file has exactly the keys of the English one, with the same
-- placeholders (%s, %d). Run from the repository root: luajit .github/scripts/check_lang.lua

local DIR = "resource/localization/"
local FILE = "/rareload.properties"
local LANGS = { "de", "es-es", "fr", "nl", "pl", "pt-br", "ru", "tr", "zh-cn" }

local function load(lang)
    local f = assert(io.open(DIR .. lang .. FILE, "r"), "missing " .. DIR .. lang .. FILE)
    local keys = {}
    for line in f:lines() do
        local key, value = line:match("^([^#=][^=]*)=(.*)$")
        if key then keys[key] = value end
    end
    f:close()
    return keys
end

local function placeholders(text)
    local out = {}
    for p in text:gmatch("%%[sd]") do out[#out + 1] = p end
    return table.concat(out, " ")
end

local en, failed = load("en"), 0
for _, lang in ipairs(LANGS) do
    local other = load(lang)
    for key, value in pairs(en) do
        if other[key] == nil then
            print(lang .. ": missing " .. key)
            failed = failed + 1
        elseif placeholders(other[key]) ~= placeholders(value) then
            print(lang .. ": placeholders differ in " .. key)
            failed = failed + 1
        end
    end
    for key in pairs(other) do
        if en[key] == nil then
            print(lang .. ": unknown key " .. key)
            failed = failed + 1
        end
    end
end

if failed > 0 then
    print(failed .. " problem(s)")
    os.exit(1)
end
print("All " .. #LANGS .. " translations match English.")
