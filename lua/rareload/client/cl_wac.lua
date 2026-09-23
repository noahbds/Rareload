-- WAC aircraft client guards (L37, from v4): WAC's client hooks crash when LocalPlayer().wac isn't set
-- up yet, which happens when a restored aircraft seats the player before WAC's own networking.
-- Only installed when WAC is present.

local function seed(ply)
    ply.wac = istable(ply.wac) and ply.wac or {}
    ply.wac.lastView = ply.wac.lastView or { origin = ply:GetPos(), angles = ply:EyeAngles(), fov = 75 }
    ply.wac.air = istable(ply.wac.air) and ply.wac.air or {}
    ply.wac.air.lastView = ply.wac.air.lastView or ply.wac.lastView
    ply.wac.mousePos = ply.wac.mousePos or Vector(0, 0, 0)
    ply.wac.airframes = ply.wac.airframes or {}
end

hook.Add("InitPostEntity", "Rareload.WAC.Detect", function()
    if not scripted_ents.GetStored("wac_hc_base") and not scripted_ents.GetStored("wac_pl_base") then return end

    hook.Add("PlayerEnteredVehicle", "Rareload.WAC.Seed", function(ply)
        if ply == LocalPlayer() then seed(ply) end
    end)
    hook.Add("CreateMove", "Rareload.WAC.Seed", function()
        local lp = LocalPlayer()
        if IsValid(lp) and lp:InVehicle() and not istable(lp.wac) then seed(lp) end
    end)
end)
