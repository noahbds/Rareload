RARELOAD.PlayerPosition = RARELOAD.PlayerPosition or {}

function RARELOAD.PlayerPosition.HandlePositionCache(ply, savedInfo)
    if not savedInfo then return end

    ply.lastSpawnPosition = savedInfo.pos
    ply.hasMovedAfterSpawn = false

    hook.Add("PlayerTick", "RARELOAD_CheckMovement_" .. ply:EntIndex(), function(ply, mv)
        if not IsValid(ply) or not ply.lastSpawnPosition then return end

        local moved = (ply:GetPos() - ply.lastSpawnPosition):LengthSqr() > 4
        if moved and not ply.hasMovedAfterSpawn then
            SavePositionToCache(ply.lastSpawnPosition)
            ply.hasMovedAfterSpawn = true
            hook.Remove("PlayerTick", "RARELOAD_CheckMovement_" .. ply:EntIndex())
        end
    end)
end

function RARELOAD.PlayerPosition.HandlePlayerSpawnPosition(ply, savedInfo, settings, debugEnabled)
    local moveType = tonumber(savedInfo.moveType) or MOVETYPE_WALK

    if not settings.spawnModeEnabled then
        local wasFlying = moveType == MOVETYPE_NOCLIP or moveType == MOVETYPE_FLY or moveType == MOVETYPE_FLYGRAVITY
        local wasSwimming = moveType == MOVETYPE_WALK or moveType == MOVETYPE_NONE

        if wasFlying or wasSwimming then
            local traceResult = TraceLine(savedInfo.pos, savedInfo.pos - Vector(0, 0, 10000), ply, MASK_SOLID_BRUSHONLY)
            if traceResult.Hit then
                local groundPos = traceResult.HitPos
                local waterTrace = TraceLine(groundPos, groundPos - Vector(0, 0, 100), ply, MASK_WATER)

                if waterTrace.Hit then
                    local foundPos = FindWalkableGround(groundPos, ply)
                    if foundPos then
                        ply:SetPos(foundPos)
                        ply:SetMoveType(MOVETYPE_NONE)
                        if debugEnabled then print("[RARELOAD DEBUG] Spawned on walkable ground.") end
                    end
                    return
                end

                ply:SetPos(groundPos)
                ply:SetMoveType(MOVETYPE_NONE)
            else
                if debugEnabled then print("[RARELOAD DEBUG] No ground found. Custom spawn prevented.") end
                return
            end
        else
            SetPlayerPositionAndEyeAngles(ply, savedInfo)
        end
    else
        timer.Simple(0, function() ply:SetMoveType(moveType) end)
        SetPlayerPositionAndEyeAngles(ply, savedInfo)
        if debugEnabled then print("[RARELOAD DEBUG] Move type set to: " .. tostring(moveType)) end
    end
end
