RARELOAD = RARELOAD or {}

if SERVER then
    util.AddNetworkString("RareloadAutoSaveTriggered")
    util.AddNetworkString("RareloadPlayerMoved")
    util.AddNetworkString("RareloadSyncAutoSaveTime")

    local function ensureDataUtils()
        if not RARELOAD or not RARELOAD.DataUtils then
            include("rareload/utils/rareload_data_utils.lua")
        end
    end

    local Autosave = {
        lastMove = {},
        lastSave = {},
        jitter = {},
        lastMoveNotify = {},
        timerName = "Rareload_AutoSaveTick",
        cachedEnabled = nil,
        cachedInterval = nil
    }

    local function getSteamID(ply)
        return IsValid(ply) and ply:SteamID() or nil
    end

    local function settings()
        return RARELOAD and RARELOAD.settings or {}
    end

    local function now()
        return CurTime()
    end

    local function minIdleSeconds(interval)
        return math.Clamp(math.floor((interval or 5) * 0.4), 1, 6)
    end

    local function ensureJitter(steamID, interval)
        if not Autosave.jitter[steamID] then
            Autosave.jitter[steamID] = math.Rand(0, math.max(0.15, math.min(0.35, (interval or 5) * 0.1)))
        end
        return Autosave.jitter[steamID]
    end

    local function isStable(ply)
        if not IsValid(ply) or not ply:Alive() then return false end
        if ply:InVehicle() then return false end

        local vel = ply:GetVelocity()
        if vel and vel:Length() > 140 then return false end

        if ply:KeyDown(IN_ATTACK) or ply:KeyDown(IN_ATTACK2) or ply:KeyDown(IN_JUMP) or ply:KeyDown(IN_DUCK) then
            return false
        end

        return true
    end

    local function stateChangedEnough(ply, lastData)
        ensureDataUtils()
        local pos = ply:GetPos()
        local ang = ply:EyeAngles()

        if not lastData then return true end

        local lastPos = RARELOAD.DataUtils.ToVector(lastData.pos) or pos
        local lastAng = RARELOAD.DataUtils.ToAngle(lastData.ang) or ang

        local dist = pos:Distance(lastPos)
        local angDelta = math.max(
            math.abs(ang.p - lastAng.p),
            math.abs(ang.y - lastAng.y),
            math.abs(ang.r - lastAng.r)
        )

        local s = settings()
        local moveThreshold = 24
        local angleThreshold = math.max(1, math.min(180, tonumber(s.angleTolerance) or 10))

        return dist >= moveThreshold or angDelta >= angleThreshold
    end

    local function sendLastMoveTime(ply, t)
        if not IsValid(ply) then return end
        local sid = getSteamID(ply)
        if not sid then return end
        local prev = Autosave.lastMoveNotify[sid] or 0
        if (t - prev) < 0.5 then return end
        Autosave.lastMoveNotify[sid] = t
        net.Start("RareloadPlayerMoved")
        net.WriteFloat(t)
        net.Send(ply)
    end

    local function syncForPlayer(ply)
        if not IsValid(ply) then return end
        local sid = getSteamID(ply)
        if not sid then return end
        net.Start("RareloadSyncAutoSaveTime")
        net.WriteFloat(Autosave.lastSave[sid] or 0)
        net.Send(ply)
        if Autosave.lastMove[sid] then
            sendLastMoveTime(ply, Autosave.lastMove[sid])
        end
    end

    local function trySave(ply)
        if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
        local s = settings()
        if not s.addonEnabled or not s.autoSaveEnabled then return end

        local sid = getSteamID(ply)
        if not sid then return end
        local interval = math.max(tonumber(s.autoSaveInterval) or 5, 1)
        local oneSecMode = interval <= 1
        local t = now()
        local lastMove = Autosave.lastMove[sid] or (t - interval)
        local lastSave = Autosave.lastSave[sid] or 0
        local jitter = oneSecMode and 0 or ensureJitter(sid, interval)

        if not oneSecMode and not isStable(ply) then return end
        if not oneSecMode and (t - lastMove) < minIdleSeconds(interval) then return end
        if (t - lastSave) < (oneSecMode and interval or (interval + jitter)) then return end

        local mapName = game.GetMap()
        RARELOAD.playerPositions = RARELOAD.playerPositions or {}
        local lastData = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][sid]
        if not stateChangedEnough(ply, lastData) then
            Autosave.lastSave[sid] = t
            syncForPlayer(ply)
            return
        end

        local ok = false
        local err
        if RARELOAD.SaveRespawnPoint then
            ok, err = RARELOAD.SaveRespawnPoint(ply, ply:GetPos(), ply:EyeAngles(), { whereMsg = "auto-save" })
            if ok == nil then ok = true end
        else
            RunConsoleCommand("save_position")
            ok = true
        end

        if ok then
            Autosave.lastSave[sid] = t
            net.Start("RareloadAutoSaveTriggered")
            net.WriteFloat(t)
            net.Send(ply)
            syncForPlayer(ply)
            if s.debugEnabled then
                print(string.format("[RARELOAD DEBUG] Auto-saved %s at t=%.2f", ply:Nick(), t))
            end
        elseif err and s.debugEnabled then
            print("[RARELOAD DEBUG] Auto-save failed: " .. tostring(err))
        end
    end

    hook.Add("SetupMove", "Rareload_AutoSave_TrackMovement", function(ply, mv, cmd)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local s = settings()
        if not s.addonEnabled or not s.autoSaveEnabled then return end

        local speed = mv:GetVelocity():Length()
        local moved = speed > 10 or mv:KeyDown(IN_FORWARD) or mv:KeyDown(IN_BACK) or mv:KeyDown(IN_MOVELEFT)
            or mv:KeyDown(IN_MOVERIGHT) or mv:KeyDown(IN_JUMP) or mv:KeyDown(IN_DUCK) or mv:KeyDown(IN_ATTACK)
            or mv:KeyDown(IN_ATTACK2)

        if moved then
            local sid = getSteamID(ply)
            if not sid then return end
            local t = now()
            Autosave.lastMove[sid] = t
            sendLastMoveTime(ply, t)
        end
    end)

    hook.Add("PlayerInitialSpawn", "Rareload_AutoSave_OnJoin", function(ply)
        local sid = getSteamID(ply)
        if not sid then return end
        Autosave.lastMove[sid] = now()
        Autosave.lastSave[sid] = now()
        timer.Simple(2, function() if IsValid(ply) then syncForPlayer(ply) end end)
    end)

    hook.Add("PlayerDisconnected", "Rareload_AutoSave_OnLeave", function(ply)
        local sid = getSteamID(ply)
        if not sid then return end
        Autosave.lastMove[sid] = nil
        Autosave.lastSave[sid] = nil
        Autosave.jitter[sid] = nil
        Autosave.lastMoveNotify[sid] = nil
    end)

    hook.Add("PlayerSpawn", "Rareload_AutoSave_OnSpawn", function(ply)
        local sid = getSteamID(ply)
        if not sid then return end
        Autosave.lastMove[sid] = now()
        timer.Simple(1, function() if IsValid(ply) then syncForPlayer(ply) end end)
    end)

    local function handleSettingsChange()
        local s = settings()
        local enabled = not not (s.addonEnabled and s.autoSaveEnabled)
        local interval = math.max(tonumber(s.autoSaveInterval) or 5, 1)

        local changed = false
        if Autosave.cachedEnabled == nil then
            Autosave.cachedEnabled = enabled
        elseif Autosave.cachedEnabled ~= enabled then
            Autosave.cachedEnabled = enabled
            changed = true
        end

        if Autosave.cachedInterval == nil then
            Autosave.cachedInterval = interval
        elseif Autosave.cachedInterval ~= interval then
            Autosave.cachedInterval = interval
            changed = true
        end

        if changed and enabled then
            local t = now()
            for _, ply in ipairs(player.GetAll()) do
                local sid = getSteamID(ply)
                if sid then
                    Autosave.lastSave[sid] = t
                    Autosave.jitter[sid] = nil
                    syncForPlayer(ply)
                end
            end
        end
    end

    timer.Create(Autosave.timerName, 0.35, 0, function()
        handleSettingsChange()
        local s = settings()
        if not s.addonEnabled or not s.autoSaveEnabled then return end
        for _, ply in ipairs(player.GetAll()) do
            trySave(ply)
        end
    end)

    RARELOAD.AutoSave = {
        SyncForPlayer = syncForPlayer,
        TouchMove = function(ply)
            local sid = getSteamID(ply)
            if not sid then return end
            Autosave.lastMove[sid] = now()
            sendLastMoveTime(ply, Autosave.lastMove[sid])
        end,
        GetLastTimes = function(ply)
            local sid = getSteamID(ply)
            return Autosave.lastMove[sid] or 0, Autosave.lastSave[sid] or 0
        end
    }
end
