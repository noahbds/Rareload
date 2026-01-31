if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.SEDNPCFreeze = RARELOAD.SEDNPCFreeze or {}
local SEDFreeze = RARELOAD.SEDNPCFreeze

SEDFreeze.FrozenNPCs = SEDFreeze.FrozenNPCs or {}
SEDFreeze.PlayerInteractions = SEDFreeze.PlayerInteractions or {}

util.AddNetworkString("SED_FreezeNPC")
util.AddNetworkString("SED_UnfreezeNPC")

function SEDFreeze.FreezeNPC(npc, player)
    if not IsValid(npc) or not IsValid(player) then return false end
    if not npc:IsNPC() then return false end

    local entIndex = npc:EntIndex()

    if SEDFreeze.FrozenNPCs[entIndex] then return false end

    local originalState = {
        scheduleType = npc:GetNPCState(),
        currentSchedule = npc:GetCurrentSchedule(),
        activity = npc:GetActivity(),
        sequence = npc:GetSequence(),
        playbackRate = npc:GetPlaybackRate(),
        movementActivity = npc:GetMovementActivity(),
        frozenBy = player,
        frozenTime = CurTime(),
        originalSpawnFlags = npc:GetSpawnFlags(),
        moveType = npc:GetMoveType(),
        solidType = npc:GetSolid()
    }

    SEDFreeze.FrozenNPCs[entIndex] = originalState
    SEDFreeze.PlayerInteractions[player:UserID()] = entIndex

    if npc.SetAIDisabled then
        npc:SetAIDisabled(true)
    end
    
    npc:AddFlags(FL_FROZEN)
    npc:SetMoveType(MOVETYPE_NONE)
    npc:SetSolid(SOLID_BBOX)
    npc:StopMoving()
    
    npc:SetNPCState(NPC_STATE_IDLE)
    
    pcall(function() npc:SetSchedule(SCHED_IDLE_STAND) end)
    
    pcall(function() npc:SetActivity(ACT_IDLE) end)
    npc:SetPlaybackRate(0)
    
    if npc.ClearGoal then
        pcall(npc.ClearGoal, npc)
    end
    
    pcall(function() npc:StopSound("*") end)
    
    pcall(function()
        npc:SetKeyValue("spawnflags", tostring(bit.bor(npc:GetSpawnFlags(), SF_NPC_WAIT_TILL_SEEN, SF_NPC_GAG)))
    end)
    npc:SetEnemy(NULL)
    npc:ClearEnemyMemory()
    
    if npc.CapabilitiesClear and npc.CapabilitiesGet then
        local ok, caps = pcall(npc.CapabilitiesGet, npc)
        if ok then
            originalState.capabilities = caps
            pcall(npc.CapabilitiesClear, npc)
        end
    end

    npc:EmitSound("common/null.wav", 0, 100, 0)

    hook.Run("RareloadSEDNPCFrozen", npc, player)

    return true
end

function SEDFreeze.UnfreezeNPC(npc, player)
    if not IsValid(npc) then return false end
    if not npc:IsNPC() then return false end

    local entIndex = npc:EntIndex()
    local originalState = SEDFreeze.FrozenNPCs[entIndex]

    if not originalState then return false end

    if IsValid(originalState.frozenBy) and originalState.frozenBy ~= player then
        return false
    end

    if npc.SetAIDisabled then
        pcall(npc.SetAIDisabled, npc, false)
    end

    npc:RemoveFlags(FL_FROZEN)
    npc:SetMoveType(originalState.moveType or MOVETYPE_STEP)
    npc:SetSolid(originalState.solidType or SOLID_BBOX)

    if originalState.originalSpawnFlags then
        pcall(function()
            npc:SetKeyValue("spawnflags", tostring(originalState.originalSpawnFlags))
        end)
    end

    local stateToRestore = originalState.scheduleType
    if stateToRestore == NPC_STATE_NONE then
        stateToRestore = NPC_STATE_IDLE
    end
    if stateToRestore then
        pcall(npc.SetNPCState, npc, stateToRestore)
    end

    if originalState.activity then
        pcall(npc.SetActivity, npc, originalState.activity)
    end

    if originalState.playbackRate then
        npc:SetPlaybackRate(originalState.playbackRate)
    end

    if originalState.sequence and originalState.sequence ~= npc:GetSequence() then
        pcall(npc.SetSequence, npc, originalState.sequence)
    end
    
    if originalState.capabilities and npc.CapabilitiesAdd then
        pcall(npc.CapabilitiesAdd, npc, originalState.capabilities)
    end

    npc:ClearEnemyMemory()

    pcall(function() npc:SetSchedule(SCHED_IDLE_STAND) end)

    SEDFreeze.FrozenNPCs[entIndex] = nil
    if IsValid(player) then
        SEDFreeze.PlayerInteractions[player:UserID()] = nil
    end

    hook.Run("RareloadSEDNPCUnfrozen", npc, player)

    return true
end

net.Receive("SED_FreezeNPC", function(len, player)
    if not IsValid(player) then return end

    local entIndex = net.ReadUInt(16)
    local npc = Entity(entIndex)

    if IsValid(npc) and npc:IsNPC() then
        local distance = player:GetPos():Distance(npc:GetPos())
        if distance <= 2500 then
            SEDFreeze.FreezeNPC(npc, player)
        end
    end
end)

net.Receive("SED_UnfreezeNPC", function(len, player)
    if not IsValid(player) then return end

    local entIndex = net.ReadUInt(16)
    local npc = Entity(entIndex)

    if IsValid(npc) and npc:IsNPC() then
        SEDFreeze.UnfreezeNPC(npc, player)
    end
end)

hook.Add("PlayerDisconnected", "SEDFreeze_PlayerDisconnect", function(player)
    local userID = player:UserID()
    local frozenEntIndex = SEDFreeze.PlayerInteractions[userID]

    if frozenEntIndex then
        local npc = Entity(frozenEntIndex)
        if IsValid(npc) then
            SEDFreeze.UnfreezeNPC(npc, player)
        end
        SEDFreeze.PlayerInteractions[userID] = nil
    end
end)

hook.Add("EntityRemoved", "SEDFreeze_EntityRemoved", function(ent)
    if ent:IsNPC() then
        local entIndex = ent:EntIndex()
        local originalState = SEDFreeze.FrozenNPCs[entIndex]

        if originalState then
            SEDFreeze.FrozenNPCs[entIndex] = nil
            if IsValid(originalState.frozenBy) then
                SEDFreeze.PlayerInteractions[originalState.frozenBy:UserID()] = nil
            end
        end
    end
end)

timer.Create("SEDFreeze_Cleanup", 60, 0, function()
    for userID, entIndex in pairs(SEDFreeze.PlayerInteractions) do
        local player = Player(userID)
        if not IsValid(player) then
            local npc = Entity(entIndex)
            if IsValid(npc) then
                SEDFreeze.UnfreezeNPC(npc, nil)
            end
            SEDFreeze.PlayerInteractions[userID] = nil
        end
    end
end)

concommand.Add("sed_freeze_test", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local tr = ply:GetEyeTrace()
    if tr.Entity and IsValid(tr.Entity) and tr.Entity:IsNPC() then
        if SEDFreeze.FreezeNPC(tr.Entity, ply) then
            ply:ChatPrint("NPC frozen for SED testing")
        else
            ply:ChatPrint("Failed to freeze NPC (already frozen?)")
        end
    else
        ply:ChatPrint("Look at an NPC to freeze it")
    end
end)

concommand.Add("sed_unfreeze_test", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local tr = ply:GetEyeTrace()
    if tr.Entity and IsValid(tr.Entity) and tr.Entity:IsNPC() then
        if SEDFreeze.UnfreezeNPC(tr.Entity, ply) then
            ply:ChatPrint("NPC unfrozen")
        else
            ply:ChatPrint("Failed to unfreeze NPC (not frozen by you?)")
        end
    else
        ply:ChatPrint("Look at an NPC to unfreeze it")
    end
end)

print("[Rareload] SED NPC Freeze system loaded (Server)")
