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
    local pos = safePos
    if type(pos) == "table" and pos.x and pos.y and pos.z then
        pos = Vector(pos.x, pos.y, pos.z)
    end
    if not util.IsInWorld(pos) then
        local fallback = Vector(0, 0, 256)
        local tr = util.TraceLine({ start = fallback, endpos = fallback - Vector(0, 0, 32768), mask =
        MASK_SOLID_BRUSHONLY })
        pos = (tr.Hit and tr.HitPos + Vector(0, 0, 16)) or fallback
    else
        local tr = util.TraceLine({ start = pos + Vector(0, 0, 64), endpos = pos - Vector(0, 0, 32768), mask =
        MASK_SOLID_BRUSHONLY })
        if tr.Hit then pos = tr.HitPos + Vector(0, 0, 16) end
    end
    ply:SetPos(pos)
    ply:SetEyeAngles(Angle(0, ply:EyeAngles().yaw, 0))
    ply:SetVelocity(Vector(0, 0, 0))
    ply:ChatPrint("Téléporté à la position: " .. tostring(safePos))
end
