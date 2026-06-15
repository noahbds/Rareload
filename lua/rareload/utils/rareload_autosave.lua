RARELOAD = RARELOAD or {}

if SERVER then
    util.AddNetworkString("RareloadAutoSaveTriggered")
    util.AddNetworkString("RareloadPlayerMoved")

    local Autosave = {
        lastMove   = {},
        moveNotify = {},
        wasMoving  = {},
        timerName  = "Rareload_AutoSaveTick"
    }

    local MOVE_NOTIFY_INTERVAL = 0.5

    local function getSteamID(ply)
        return IsValid(ply) and ply:SteamID() or nil
    end

    local function getSetting(ply, key, default)
        if RARELOAD and RARELOAD.GetPlayerSetting and IsValid(ply) then
            return RARELOAD.GetPlayerSetting(ply, key, default)
        end
        local s = RARELOAD and RARELOAD.settings or {}
        if s[key] ~= nil then return s[key] end
        return default
    end

    local function now()
        return CurTime()
    end

    local function autoSaveOn(ply)
        return getSetting(ply, "addonEnabled", true) and getSetting(ply, "autoSaveEnabled", false)
    end

    local function isSafeToSave(ply)
        if not (IsValid(ply) and ply:Alive()) then return false end
        if ply:InVehicle() then return true end
        local mt = ply:GetMoveType()
        if mt == MOVETYPE_NOCLIP or mt == MOVETYPE_FLY or mt == MOVETYPE_FLYGRAVITY or mt == MOVETYPE_LADDER then
            return true
        end
        return ply:IsOnGround()
    end

    local function stateChangedEnough(ply, lastData)
        if not lastData then return true end

        local pos = ply:GetPos()
        local ang = ply:EyeAngles()
        local lastPos = RARELOAD.DataUtils.ToVector(lastData.pos) or pos
        local lastAng = RARELOAD.DataUtils.ToAngle(lastData.ang) or ang

        local dist = pos:Distance(lastPos)
        local angDelta = math.max(
            math.abs(ang.p - lastAng.p),
            math.abs(ang.y - lastAng.y),
            math.abs(ang.r - lastAng.r)
        )

        local angleThreshold = math.Clamp(tonumber(getSetting(ply, "angleTolerance", 10)) or 10, 1, 180)
        return dist >= 24 or angDelta >= angleThreshold
    end

    local function notifyMove(ply, sid, t)
        net.Start("RareloadPlayerMoved")
        net.WriteFloat(t)
        net.Send(ply)
        Autosave.moveNotify[sid] = t
    end

    hook.Add("SetupMove", "Rareload_AutoSave_TrackMovement", function(ply, mv)
        if not (IsValid(ply) and ply:IsPlayer()) then return end
        if not autoSaveOn(ply) then return end

        local sid = getSteamID(ply)
        if not sid then return end

        local moving = mv:GetVelocity():Length() > 20
            or mv:KeyDown(IN_FORWARD) or mv:KeyDown(IN_BACK)
            or mv:KeyDown(IN_MOVELEFT) or mv:KeyDown(IN_MOVERIGHT)
            or mv:KeyDown(IN_JUMP)

        if moving then
            local t = now()
            Autosave.lastMove[sid] = t
            Autosave.wasMoving[sid] = true
            if (t - (Autosave.moveNotify[sid] or 0)) >= MOVE_NOTIFY_INTERVAL then
                notifyMove(ply, sid, t)
            end
        elseif Autosave.wasMoving[sid] then
            Autosave.wasMoving[sid] = nil
            notifyMove(ply, sid, Autosave.lastMove[sid] or now())
        end
    end)

    local function trySave(ply)
        if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return end
        if not autoSaveOn(ply) then return end
        if ply._rareloadSpawnTime and (now() - ply._rareloadSpawnTime) < 3 then return end

        local sid = getSteamID(ply)
        if not sid then return end

        local lastMove = Autosave.lastMove[sid]
        if not lastMove then return end

        if Autosave.wasMoving[sid] then return end

        local interval = math.max(tonumber(getSetting(ply, "autoSaveInterval", 5)) or 5, 0)
        if interval > 0 and (now() - lastMove) < interval then return end
        if not isSafeToSave(ply) then return end

        local mapName = game.GetMap()
        RARELOAD.playerPositions = RARELOAD.playerPositions or {}
        local lastData = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][sid]
        if not stateChangedEnough(ply, lastData) then return end

        local ok, err = false, nil
        if RARELOAD.SaveRespawnPoint then
            ok, err = RARELOAD.SaveRespawnPoint(ply, ply:GetPos(), ply:EyeAngles(),
                { whereMsg = "auto-save", silent = true, skipWorldSnapshot = true })
            if ok == nil then ok = true end
        else
            print("[RARELOAD] Warning: SaveRespawnPoint not available for auto-save")
        end

        if ok then
            net.Start("RareloadAutoSaveTriggered")
            net.WriteFloat(now())
            net.Send(ply)
            if getSetting(ply, "debugEnabled", false) then
                print(string.format("[RARELOAD DEBUG] Auto-saved %s (idle for %ds)", ply:Nick(), interval))
            end
        elseif err and getSetting(ply, "debugEnabled", false) then
            print("[RARELOAD DEBUG] Auto-save failed: " .. tostring(err))
        end
    end

    hook.Add("PlayerInitialSpawn", "Rareload_AutoSave_OnJoin", function(ply)
        local sid = getSteamID(ply)
        if not sid then return end
        Autosave.lastMove[sid] = now()
        timer.Simple(2, function()
            if IsValid(ply) and Autosave.lastMove[sid] then
                net.Start("RareloadPlayerMoved")
                net.WriteFloat(Autosave.lastMove[sid])
                net.Send(ply)
            end
        end)
    end)

    hook.Add("PlayerSpawn", "Rareload_AutoSave_OnSpawn", function(ply)
        local sid = getSteamID(ply)
        if not sid then return end
        Autosave.lastMove[sid] = now()
        Autosave.wasMoving[sid] = nil
        timer.Simple(0.1, function()
            if IsValid(ply) and Autosave.lastMove[sid] then
                net.Start("RareloadPlayerMoved")
                net.WriteFloat(Autosave.lastMove[sid])
                net.Send(ply)
            end
        end)
    end)

    hook.Add("PlayerDisconnected", "Rareload_AutoSave_OnLeave", function(ply)
        local sid = getSteamID(ply)
        if sid then
            Autosave.lastMove[sid]   = nil
            Autosave.moveNotify[sid] = nil
            Autosave.wasMoving[sid]  = nil
        end
    end)

    timer.Create(Autosave.timerName, 0.35, 0, function()
        for _, ply in ipairs(player.GetAll()) do
            trySave(ply)
        end
    end)
end
