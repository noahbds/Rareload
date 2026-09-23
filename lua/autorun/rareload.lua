-- Rareload loader: includes every Rareload file in a fixed order (REWRITE_PLAN.md §10.3, §13.1).
-- Files only register at include time; real work starts on the RareloadLoaded hook.

RARELOAD = RARELOAD or {}
RARELOAD.version = "5.0.0-dev"
RARELOAD.API = 1
-- Bumped on every (re)load so registries can tell a reload apart from a duplicate registration.
RARELOAD.loadGen = (RARELOAD.loadGen or 0) + 1

-- Shared files load first and in this order, because later files register into them.
local SHARED = { "sh_util", "sh_perms", "sh_net", "sh_config" }

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
-- cl_ui and cl_state first: the other client files use them while loading.
local CLIENT_FIRST = { "rareload/client/cl_ui.lua", "rareload/client/cl_state.lua" }
for _, path in ipairs(CLIENT_FIRST) do includeClient(path) end
eachFile("client/", function(path)
    if not table.HasValue(CLIENT_FIRST, path) then includeClient(path) end
end)
-- The world display's files depend on each other in this order (§21.7).
for _, name in ipairs({ "cl_tracking", "cl_phantoms", "cl_panels", "cl_interact", "cl_highlight" }) do
    includeClient("rareload/client/world/" .. name .. ".lua")
end

hook.Run("RareloadLoaded")

MsgC(Color(120, 200, 255), "[Rareload] ", color_white, "Rareload " .. RARELOAD.version .. " loaded\n")
