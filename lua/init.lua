-- init.lua

-- Global table setup
RARELOAD = RARELOAD or {}
RARELOAD.PlayerData = {}
RARELOAD.VehicleData = {}
RARELOAD.NPCData = {}
RARELOAD.EntityData = {}
RARELOAD.settings = {}
RARELOAD.playerPositions = {}

print("Rareload: Initializing...")

-- Client files (make available to clients)
AddCSLuaFile("rareload/client/cl_rareload_hooks.lua")
AddCSLuaFile("rareload/shared/sh_config.lua")
AddCSLuaFile("rareload/tools/cl_rareload_tool.lua")

-- Shared files
include("rareload/shared/sh_config.lua")

-- Server files
include("rareload/server/sv_init_rareload.lua")
include("rareload/server/sv_rareload_commands.lua")
include("rareload/server/sv_rareload_hooks.lua")
include("rareload/server/sv_rareload_debug.lua")

-- Handler modules
include("rareload/server/handlers/sv_handler_entities.lua")
include("rareload/server/handlers/sv_handler_npc.lua")
include("rareload/server/handlers/sv_handler_vehicles.lua")
include("rareload/server/handlers/sv_handler_inventory.lua")

-- Data modules
include("rareload/server/data/sv_entity_data.lua")
include("rareload/server/data/sv_npc_data.lua")
include("rareload/server/data/sv_player_data.lua")
include("rareload/server/data/sv_vehicle_data.lua")

-- Tools
include("rareload/tools/sv_rareload_tool.lua")

-- Client hooks (needed on server too)
include("rareload/client/cl_rareload_hooks.lua")

print("Rareload: All files loaded")

-- File existence checking
local function checkFileExists(filePath)
    if not file.Exists(filePath, "LUA") then
        print("[RARELOAD ERROR] Missing file: " .. filePath)
    end
end

-- Check all included files
local filesToCheck = {
    "rareload/server/sv_init_rareload.lua",
    "rareload/server/sv_rareload_commands.lua",
    "rareload/server/sv_rareload_hooks.lua",
    "rareload/server/sv_rareload_debug.lua",
    "rareload/server/handlers/sv_handler_entities.lua",
    "rareload/server/handlers/sv_handler_npc.lua",
    "rareload/server/handlers/sv_handler_vehicles.lua",
    "rareload/server/handlers/sv_handler_inventory.lua",
    "rareload/server/data/sv_entity_data.lua",
    "rareload/server/data/sv_npc_data.lua",
    "rareload/server/data/sv_player_data.lua",
    "rareload/server/data/sv_vehicle_data.lua",
    "rareload/client/cl_rareload_hooks.lua",
    "rareload/tools/sv_rareload_tool.lua",
    "rareload/tools/cl_rareload_tool.lua",
    "rareload/shared/sh_config.lua"
}

for _, filePath in ipairs(filesToCheck) do
    checkFileExists(filePath)
end
