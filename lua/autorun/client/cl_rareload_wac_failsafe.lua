-- ===========================================================================
-- WAC AIRCRAFT CLIENT FAILSAFE
-- ===========================================================================

if not CLIENT then return end

local function IsWACVehicle(veh)
    if not IsValid(veh) then return false end
    if veh.wac_aircraft then return true end
    if isfunction(veh.GetNWEntity) and IsValid(veh:GetNWEntity("wac_aircraft")) then return true end
    return string.find(string.lower(veh:GetClass() or ""), "^wac_") ~= nil
end

local function SeedLastView(p)
    if not IsValid(p) then return end
    p.wac = istable(p.wac) and p.wac or {}
    p.wac.air = istable(p.wac.air) and p.wac.air or {}
    if not istable(p.wac.air.lastView) then
        p.wac.air.lastView = { origin = p:GetPos(), angles = p:EyeAngles(), fov = 75 }
    end
end

hook.Add("PlayerEnteredVehicle", "Rareload_WAC_SeedView", function(ply, veh)
    if ply == LocalPlayer() and IsWACVehicle(veh) then SeedLastView(ply) end
end)

hook.Add("PlayerBindPress", "Rareload_WAC_Client_Exit_Bind", function(ply, bind, pressed)
    if not (pressed and string.find(bind, "+use") and IsValid(ply) and ply:InVehicle()) then return end
    local veh = ply:GetVehicle()
    if not IsValid(veh) then return end
    local aircraft = veh.wac_aircraft
        or (isfunction(veh.GetNWEntity) and veh:GetNWEntity("wac_aircraft"))
        or (isfunction(veh.GetParent) and veh:GetParent())
    if (IsValid(aircraft) and string.find(string.lower(aircraft:GetClass() or ""), "^wac_"))
        or string.find(string.lower(veh:GetClass() or ""), "^wac_") then
        RunConsoleCommand("wac_air_input", "Exit", "1")
    end
end)
