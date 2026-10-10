-- Rareload loader: includes every Rareload file in a fixed order

RARELOAD = RARELOAD or {}

RARELOAD.version = "5.2"
RARELOAD.API = 1
RARELOAD.loadGen = (RARELOAD.loadGen or 0) + 1

-- Legacy (v4) Rareload shares the RARELOAD global and the tool file, so running both breaks
-- each other. If it is installed, stay disabled and tell the player to remove it.
local LEGACY_WSID = "3807939033"
local LEGACY_FILES = {
    "autorun/rareload_init.lua",
    "rareload/core/rareload_core.lua"
}

local function legacyInstalled()
    for _, path in ipairs(LEGACY_FILES) do
        if file.Exists(path, "LUA") then return true end
    end

    for _, addon in ipairs(engine.GetAddons()) do
        if tostring(addon.wsid) == LEGACY_WSID and addon.mounted then return true end
    end

    return false
end

RARELOAD.legacyConflict = legacyInstalled()

if RARELOAD.legacyConflict then
    local function phrase(key, fallback)
        if not CLIENT then return fallback end
        local text = language.GetPhrase(key)
        return text ~= key and text or fallback
    end

    local title = phrase("rareload.legacy.title", "Rareload is disabled")
    local body = phrase("rareload.legacy.body",
        "The legacy version of Rareload is installed. It conflicts with this version, so Rareload "
            .. "has been disabled. Unsubscribe from the legacy Rareload addon (Workshop ID "
            .. LEGACY_WSID .. ") and restart the game.")

    MsgC(Color(255, 90, 90), "[Rareload] ", color_white, title .. ": " .. body .. "\n")

    if CLIENT then
        hook.Add("InitPostEntity", "RareloadLegacyConflict", function()
            timer.Simple(2, function()
                chat.AddText(Color(255, 90, 90), "[Rareload] ", color_white, body)
                Derma_Message(body, title, "OK")
            end)
        end)
    end

    return
end

local SHARED = {
    "sh_util",
    "sh_perms",
    "sh_net",
    "sh_config"
}

local function includeShared(path)
    if SERVER then
        AddCSLuaFile(path)
    end

    include(path)
end

local function includeClient(path)
    if SERVER then
        AddCSLuaFile(path)
    else
        include(path)
    end
end

local function eachFile(dir, fn)
    local files = file.Find("rareload/" .. dir .. "*.lua", "LUA") or {}

    table.sort(files)

    for _, name in ipairs(files) do
        fn("rareload/" .. dir .. name)
    end
end

-- Shared core
for _, name in ipairs(SHARED) do
    local path = "rareload/shared/" .. name .. ".lua"

    if file.Exists(path, "LUA") then
        includeShared(path)
    else
        ErrorNoHalt("[Rareload] missing core file " .. path .. "\n")
    end
end

-- Server
if SERVER then
    eachFile("server/", include)
    eachFile("server/modules/", include)
end

-- cl_ui and cl_state must load before the other client files.
local CLIENT_FIRST = {
    "rareload/client/cl_ui.lua",
    "rareload/client/cl_state.lua"
}

for _, path in ipairs(CLIENT_FIRST) do
    includeClient(path)
end

eachFile("client/", function(path)
    if not table.HasValue(CLIENT_FIRST, path) then
        includeClient(path)
    end
end)

-- World display dependencies.
for _, name in ipairs({
    "cl_tracking",
    "cl_phantoms",
    "cl_panels",
    "cl_interact",
    "cl_highlight"
}) do
    includeClient("rareload/client/world/" .. name .. ".lua")
end

hook.Run("RareloadLoaded")

MsgC(
    Color(120, 200, 255),
    "[Rareload] ",
    color_white,
    "Rareload " .. RARELOAD.version .. " loaded\n"
)
