-- Sets the tool gun back to a saved tool and its settings (modules/tool.lua). Only that tool's own
-- client convars are set, so a save can't run anything else. The tools are read from the tool gun's
-- stored class: on a respawn this arrives before the player's tool gun exists on the client.

RARELOAD.Net.On("tool.apply", function(payload)
    if not isstring(payload.mode) or not string.match(payload.mode, "^[%w_]+$") then return end
    local stored = weapons.GetStored("gmod_tool")
    local tool = istable(stored) and istable(stored.Tool) and stored.Tool[payload.mode]
    if not istable(tool) then return end
    local known = istable(tool.ClientConVar) and tool.ClientConVar or {}
    for name, value in pairs(istable(payload.convars) and payload.convars or {}) do
        name = tostring(name)
        if known[name] ~= nil and GetConVar(payload.mode .. "_" .. name) then
            RunConsoleCommand(payload.mode .. "_" .. name, tostring(value))
        end
    end
    RunConsoleCommand("gmod_toolmode", payload.mode)
end)
