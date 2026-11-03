-- Sets the tool gun back to a saved tool and its settings (modules/tool.lua). Only that tool's own
-- client convars are set, so a save can't run anything else.

RARELOAD.Net.On("tool.apply", function(p)
    if not isstring(p.mode) or not string.match(p.mode, "^[%w_]+$") then return end
    local gun = LocalPlayer():GetWeapon("gmod_tool")
    local tool = IsValid(gun) and istable(gun.Tool) and gun.Tool[p.mode]
    if not tool then return end
    local known = istable(tool.ClientConVar) and tool.ClientConVar or {}
    for name, value in pairs(istable(p.convars) and p.convars or {}) do
        name = tostring(name)
        if known[name] ~= nil and GetConVar(p.mode .. "_" .. name) then
            RunConsoleCommand(p.mode .. "_" .. name, tostring(value))
        end
    end
    RunConsoleCommand("gmod_toolmode", p.mode)
end)
