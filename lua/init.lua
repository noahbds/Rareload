-- init.lua

-- Add client-side files to be sent to clients
AddCSLuaFile("autorun/server/sv_init_rareload.lua")
AddCSLuaFile("autorun/server/sv_rareload_commands.lua")
AddCSLuaFile("autorun/server/sv_rareload_hooks.lua")
AddCSLuaFile("weapons/gmod_tool/stools/sh_rareload_tool.lua")
AddCSLuaFile("weapons/gmod_tool/stools/cl_rareload_tool.lua")
AddCSLuaFile("weapons/gmod_tool/stools/sv_rareload_tool.lua")

-- Include server-side files
include("autorun/server/sv_init_rareload.lua")
include("autorun/server/sv_rareload_commands.lua")
include("autorun/server/sv_rareload_hooks.lua")
include("weapons/gmod_tool/stools/sh_rareload_tool.lua")
include("weapons/gmod_tool/stools/cl_rareload_tool.lua")
include("weapons/gmod_tool/stools/sv_rareload_tool.lua")

-- Print a message to the server console indicating that the addon is loading
print("Rareload: Loading shared files")

-- Check if the necessary files are loaded correctly
local function checkFileExists(filePath)
    if not file.Exists(filePath, "LUA") then
        print("[RARELOAD ERROR] Missing file: " .. filePath)
    end
end

-- List of files to check
local filesToCheck = {
    "autorun/server/sv_init_rareload.lua",
    "autorun/server/sv_rareload_commands.lua",
    "autorun/server/sv_rareload_hooks.lua",
    "weapons/gmod_tool/stools/sh_rareload_tool.lua",
    "weapons/gmod_tool/stools/cl_rareload_tool.lua",
    "weapons/gmod_tool/stools/sv_rareload_tool.lua"
}

-- Check each file
for _, filePath in ipairs(filesToCheck) do
    checkFileExists(filePath)
end
