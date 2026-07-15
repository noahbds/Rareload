-- Rareload localization.
-- Locale files live in lua/rareload/shared/lang/<code>.lua and return a flat
-- table of key -> string. en.lua is the source of truth: any key missing from
-- another locale falls back to English, then to the raw key.
--
-- Usage: RARELOAD.L("ev.title")  or  RARELOAD.L("screen.saving_in", 5)

RARELOAD = RARELOAD or {}
RARELOAD.Lang = RARELOAD.Lang or {}
local Lang = RARELOAD.Lang

Lang.Fallback = "en"
Lang.Locales = {}

local LANG_DIR = "rareload/shared/lang/"

local function LoadLocales()
    Lang.Locales = {}
    for _, fileName in ipairs(file.Find(LANG_DIR .. "*.lua", "LUA") or {}) do
        if SERVER then AddCSLuaFile(LANG_DIR .. fileName) end
        local ok, strings = pcall(include, LANG_DIR .. fileName)
        if ok and istable(strings) then
            Lang.Locales[string.lower(string.StripExtension(fileName))] = strings
        else
            ErrorNoHalt("[RARELOAD] Failed to load locale file: " .. fileName .. "\n")
        end
    end
end

-- Which locale should be active for this client. "auto" (the default) follows
-- the game's own language (gmod_language, mirrors the Steam UI language).
local function ResolveCode()
    if SERVER then return Lang.Fallback end

    local code = ""
    local cv = GetConVar("rareload_language")
    if cv then code = string.lower(cv:GetString()) end

    if code == "" or code == "auto" then
        local gl = GetConVar("gmod_language")
        code = string.lower(gl and gl:GetString() or "")
    end

    if Lang.Locales[code] then return code end

    -- "pt-br" -> "pt", "zh-cn" -> "zh"
    local base = string.match(code, "^(%a+)")
    if base and Lang.Locales[base] then return base end

    return Lang.Fallback
end

local active = {}

local function RebuildActive()
    local code = ResolveCode()
    Lang.ActiveCode = code

    local en = Lang.Locales[Lang.Fallback] or {}
    if code == Lang.Fallback then
        active = en
    else
        -- Pre-merge so every lookup is a single table access at draw time.
        active = table.Copy(en)
        for k, v in pairs(Lang.Locales[code] or {}) do
            active[k] = v
        end
    end

    hook.Run("RareloadLanguageChanged", code)
end

-- Translate a key; extra args are passed through string.format.
function RARELOAD.L(key, ...)
    local str = active[key] or key
    if select("#", ...) == 0 then return str end

    local ok, out = pcall(string.format, str, ...)
    if ok then return out end

    -- A translation with broken placeholders must not error the UI:
    -- retry with the English string, then give up and return it unformatted.
    local en = Lang.Locales[Lang.Fallback]
    local enStr = en and en[key]
    if enStr and enStr ~= str then
        ok, out = pcall(string.format, enStr, ...)
        if ok then return out end
    end
    return str
end

-- Like RARELOAD.L but returns nil instead of the key when untranslated,
-- for call sites that have their own fallback text (e.g. tunable defs).
function Lang.Get(key)
    return active[key]
end

-- Sorted locale codes, for the language dropdown.
function Lang.GetAvailable()
    local codes = {}
    for code in pairs(Lang.Locales) do
        codes[#codes + 1] = code
    end
    table.sort(codes)
    return codes
end

-- Human-readable name of a locale (each locale file sets __name).
function Lang.GetName(code)
    local strings = Lang.Locales[code]
    return (strings and strings.__name) or string.upper(code or "")
end

if CLIENT then
    CreateClientConVar("rareload_language", "auto", true, false,
        "Rareload UI language ('auto' follows gmod_language)")

    cvars.AddChangeCallback("rareload_language", RebuildActive, "RareloadLang")
    cvars.AddChangeCallback("gmod_language", RebuildActive, "RareloadLang")
end

LoadLocales()
RebuildActive()

return Lang
