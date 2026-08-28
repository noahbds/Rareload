-- ===========================================================================
-- WAC AIRCRAFT INPUT & VIEW FAILSAFE
-- Prevents wac_aircraft_input.lua and wac_aircraft.lua from crashing when a
-- player is programmatically seated via ply:EnterVehicle() instead of the USE key.
-- ===========================================================================

if not CLIENT then return end

local function EnsureWAC(ply)
    ply = ply or LocalPlayer()
    if not IsValid(ply) then return end

    local ang = isfunction(ply.EyeAngles) and ply:EyeAngles() or Angle(0, 0, 0)
    local pos = isfunction(ply.GetPos) and ply:GetPos() or Vector(0, 0, 0)

    -- 1. Base player WAC table
    if not ply.wac or not istable(ply.wac) then
        ply.wac = {}
    end

    -- 2. Mouse input sub-table (expected by wac_aircraft_input.lua)
    if not ply.wac.mouse or not istable(ply.wac.mouse) then
        ply.wac.mouse = {
            lastView = ang,
            x = 0,
            y = 0
        }
    else
        if not ply.wac.mouse.lastView then ply.wac.mouse.lastView = ang end
    end

    if not ply.wac.lastView then
        ply.wac.lastView = ang
    end

    -- 3. Aircraft view state sub-table (expected by wac_aircraft.lua CalcView)
    if not ply.wac.air or not istable(ply.wac.air) then
        ply.wac.air = {}
    end

    if not ply.wac.air.lastView or not istable(ply.wac.air.lastView) then
        ply.wac.air.lastView = {
            origin = pos,
            angles = ang,
            fov = 75
        }
    end
end

-- Hook into all early client input and view pipeline hooks
hook.Add("CreateMove", "Rareload_WAC_Failsafe_CreateMove", function(cmd)
    EnsureWAC(LocalPlayer())
end)

hook.Add("InputMouseApply", "Rareload_WAC_Failsafe_InputMouse", function(cmd, x, y, ang)
    EnsureWAC(LocalPlayer())
end)

hook.Add("CalcView", "Rareload_WAC_Failsafe_CalcView", function(ply, origin, angles, fov)
    EnsureWAC(ply or LocalPlayer())
end)

hook.Add("PlayerEnteredVehicle", "Rareload_WAC_Failsafe_Enter", function(ply, veh)
    EnsureWAC(ply or LocalPlayer())
end)

hook.Add("Think", "Rareload_WAC_Failsafe_Think", function()
    local ply = LocalPlayer()
    if IsValid(ply) and ply:InVehicle() then
        EnsureWAC(ply)
    end
end)

hook.Add("InitPostEntity", "Rareload_WAC_Failsafe_Init", function()
    EnsureWAC(LocalPlayer())
end)

-- Ensure client pressing +use (E) explicitly sends valid Exit arguments
hook.Add("PlayerBindPress", "Rareload_WAC_Client_Exit_Bind", function(ply, bind, pressed)
    if pressed and string.find(bind, "+use") and IsValid(ply) and ply:InVehicle() then
        local veh = ply:GetVehicle()
        if IsValid(veh) then
            local aircraft = veh.wac_aircraft or (veh.GetNWEntity and veh:GetNWEntity("wac_aircraft")) or (veh.GetParent and veh:GetParent())
            if (IsValid(aircraft) and string.find(string.lower(aircraft:GetClass() or ""), "^wac_")) or string.find(string.lower(veh:GetClass() or ""), "^wac_") then
                RunConsoleCommand("wac_air_input", "Exit", "1")
            end
        end
    end
end)

-- Immediate fallback if LocalPlayer() is already valid
if IsValid(LocalPlayer()) then
    EnsureWAC(LocalPlayer())
end
