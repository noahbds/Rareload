-- Rareload loader: includes every Rareload file in a fixed order (REWRITE_PLAN.md §10.3, §13.1).
-- Files only register at include time; real work starts on the RareloadLoaded hook.

RARELOAD = RARELOAD or {}
RARELOAD.version = "5.0.0-dev"
RARELOAD.API = 1

-- Shared files load first and in this order, because later files register into them.
local SHARED = { "sh_core", "sh_util", "sh_config", "sh_perms", "sh_net" }

local function includeShared(path)
    if SERVER then AddCSLuaFile(path) end
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

for _, name in ipairs(SHARED) do
    local path = "rareload/" .. name .. ".lua"
    if file.Exists(path, "LUA") then
        includeShared(path)
    else
        ErrorNoHalt("[Rareload] missing core file " .. path .. "\n")
    end
end

if SERVER then
    eachFile("server/", include)
    eachFile("server/modules/", include)
end
eachFile("client/", includeClient)
eachFile("client/world/", includeClient)

hook.Run("RareloadLoaded")

MsgC(Color(120, 200, 255), "[Rareload] ", color_white, "Rareload " .. RARELOAD.version .. " loaded\n")
