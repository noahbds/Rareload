-- Rareload loader: includes every Rareload file in a fixed order

RARELOAD = RARELOAD or {}

RARELOAD.version = "5.0"
RARELOAD.API = 1
RARELOAD.loadGen = (RARELOAD.loadGen or 0) + 1

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
