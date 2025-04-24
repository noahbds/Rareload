function RARELOAD.HandleTeleportRequest(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:IsAdmin() then return end
    local pos = net.ReadVector()
    if not pos or pos:IsZero() then return end
    local trace = {}
    trace.start = pos + Vector(0, 0, 50)
    trace.endpos = pos - Vector(0, 0, 50)
    trace.filter = ply
    local tr = util.TraceLine(trace)
    local safePos = tr.HitPos + Vector(0, 0, 10)
    if ply:InVehicle() then ply:ExitVehicle() end
    ply:SetPos(safePos)
    ply:SetEyeAngles(Angle(0, ply:EyeAngles().yaw, 0))
    ply:SetVelocity(Vector(0, 0, 0))
    ply:ChatPrint("Téléporté à la position: " .. tostring(safePos))
end
