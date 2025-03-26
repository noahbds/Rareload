-- init.lua

AddCSLuaFile("autorun/client/cl_rareload_hooks.lua")
AddCSLuaFile("weapons/gmod_tool/stools/sv_rareload_tool.lua")

include("autorun/server/sv_init_rareload.lua")
include("autorun/server/sv_rareload_commands.lua")
include("autorun/server/sv_rareload_hooks.lua")
include("autorun/server/sv_rareload_debug.lua")
include("lua/autorun/server/sv_rareload_handler_entities.lua")
include("lua/autorun/server/sv_rareload_handler_npc.lua")
include("lua/autorun/server/sv_rareload_handler_vehicles.lua")
include("lua/autorun/server/sv_rareload_handler_inventory.lua")
include("lua/autorun/client/cl_rareload_hooks.lua")
include("weapons/gmod_tool/stools/sv_rareload_tool.lua")


print("Rareload: Loading shared files")

local function checkFileExists(filePath)
    if not file.Exists(filePath, "LUA") then
        print("[RARELOAD ERROR] Missing file: " .. filePath)
    end
end

local filesToCheck = {
    "autorun/server/sv_init_rareload.lua",
    "autorun/server/sv_rareload_commands.lua",
    "autorun/server/sv_rareload_hooks.lua",
    "autorun/server/sv_rareload_debug.lua",
    "weapons/gmod_tool/stools/sv_rareload_tool.lua",
    "autorun/client/cl_rareload_hooks.lua"
}

for _, filePath in ipairs(filesToCheck) do
    checkFileExists(filePath)
end
