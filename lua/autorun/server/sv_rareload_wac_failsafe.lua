-- ===========================================================================
-- WAC AIRCRAFT SERVER INPUT & EXIT FAILSAFE
-- Prevents wac_hc_base and wac_aircraft_input from crashing on nil comparisons
-- and guarantees players can always cleanly enter and exit WAC aircraft.
-- ===========================================================================

if not SERVER then return end

local function PatchWACEntity(ent)
    if not IsValid(ent) then return end
    local class = string.lower(ent:GetClass() or "")
    if not string.find(class, "^wac_") then return end

    -- Initialize all internal numeric and state fields used by WAC
    ent.rotorRpm        = ent.rotorRpm or 0
    ent.engineRpm       = ent.engineRpm or 0
    ent.engineHealth    = ent.engineHealth or 100
    ent.LastDamageTaken = ent.LastDamageTaken or 0
    ent.LastActivated   = ent.LastActivated or 0
    ent.NextWepSwitch   = ent.NextWepSwitch or 0
    ent.NextCamSwitch   = ent.NextCamSwitch or 0
    ent.LastPhys        = ent.LastPhys or 0
    ent.nextUpdate      = ent.nextUpdate or 0
    ent.LastExit        = ent.LastExit or 0
    ent.nextExit        = ent.nextExit or 0
    ent.passengers      = ent.passengers or {}
    ent.controls        = ent.controls or { throttle = -1, pitch = 0, yaw = 0, roll = 0 }

    -- Wrap receiveInput to prevent nil comparisons from crashing and blocking vehicle exit
    if isfunction(ent.receiveInput) and not ent._Rareload_PatchedReceiveInput then
        ent._Rareload_PatchedReceiveInput = true
        local origReceiveInput = ent.receiveInput

        ent.receiveInput = function(self, name, value, seatIndex)
            self.rotorRpm      = self.rotorRpm or 0
            self.engineRpm     = self.engineRpm or 0
            self.LastExit      = self.LastExit or 0
            self.nextExit      = self.nextExit or 0
            self.LastActivated = self.LastActivated or 0
            self.nextUpdate    = self.nextUpdate or 0
            self.passengers    = self.passengers or {}

            name = tostring(name or "")
            value = tonumber(value) or 1
            seatIndex = tonumber(seatIndex) or 1

            local passenger = self.passengers[seatIndex]
            if not IsValid(passenger) and IsValid(self.passengers[1]) then
                passenger = self.passengers[1]
            end

            -- If player is pressing Exit, guarantee they can exit without getting trapped
            if string.lower(name) == "exit" and value > 0.5 then
                if IsValid(passenger) then
                    passenger:ExitVehicle()
                    return
                end
            end

            local ok, err = pcall(origReceiveInput, self, name, value, seatIndex)
            if not ok then
                if string.lower(name) == "exit" and value > 0.5 and IsValid(passenger) then
                    passenger:ExitVehicle()
                end
            end
        end
    end
end

-- Override wac_air_input command on the server to prevent missing parameter comparison crashes
concommand.Add("wac_air_input", function(p, c, a)
    if not IsValid(p) or not p:Alive() then return end
    local v = p:GetVehicle()
    if not IsValid(v) then return end
    local e = v.wac_aircraft or (v.GetNWEntity and v:GetNWEntity("wac_aircraft")) or (v.GetParent and v:GetParent())
    if IsValid(e) then
        PatchWACEntity(e)
        local name = tostring(a and a[1] or "")
        local val = tonumber(a and a[2]) or 1
        local passengerId = tonumber(p:GetNWInt("wac_passenger_id", 1)) or 1
        if passengerId <= 0 then passengerId = 1 end

        if string.lower(name) == "exit" and val > 0.5 then
            p:ExitVehicle()
            return
        end

        if isfunction(e.receiveInput) then
            pcall(e.receiveInput, e, name, val, passengerId)
        end
    end
end)

-- Global Server Failsafes: Ensure WAC passenger indexing and tables are always synchronized
hook.Add("PlayerEnteredVehicle", "Rareload_WAC_Server_Enter_Failsafe", function(ply, veh)
    if not IsValid(ply) or not IsValid(veh) then return end

    ply.wac = ply.wac or {}
    if ply.wac.mouseInput == nil then ply.wac.mouseInput = false end

    local aircraft = veh.wac_aircraft or (veh.GetNWEntity and veh:GetNWEntity("wac_aircraft")) or (veh.GetParent and veh:GetParent())
    if IsValid(aircraft) and string.find(string.lower(aircraft:GetClass() or ""), "^wac_") then
        PatchWACEntity(aircraft)

        local seatIndex = veh.wac_seatinfo or veh.wac_passenger_id or (veh.GetNWInt and veh:GetNWInt("wac_passenger_id", 0)) or 0
        if seatIndex <= 0 and istable(aircraft.seats) then
            for idx, s in pairs(aircraft.seats) do
                if s == veh then
                    seatIndex = tonumber(idx) or 1
                    break
                end
            end
        end
        if seatIndex <= 0 then seatIndex = 1 end

        aircraft.passengers = aircraft.passengers or {}
        aircraft.passengers[seatIndex] = ply

        veh.wac_seatinfo = seatIndex
        veh.wac_passenger_id = seatIndex
        if isfunction(veh.SetNWInt) then veh:SetNWInt("wac_passenger_id", seatIndex) end
        if isfunction(veh.SetNWEntity) then veh:SetNWEntity("wac_aircraft", aircraft) end

        if isfunction(ply.SetNWInt) then ply:SetNWInt("wac_passenger_id", seatIndex) end
        if isfunction(ply.SetNWEntity) then ply:SetNWEntity("wac_aircraft", aircraft) end
    end
end)

hook.Add("PlayerLeaveVehicle", "Rareload_WAC_Server_Leave_Failsafe", function(ply, veh)
    if IsValid(ply) then
        ply.wac = ply.wac or {}
        ply.wac.mouseInput = false
    end
    if IsValid(veh) and veh.GetNWEntity then
        local aircraft = veh:GetNWEntity("wac_aircraft")
        if IsValid(aircraft) and istable(aircraft.passengers) then
            local seatIndex = veh:GetNWInt("wac_passenger_id", 0)
            if seatIndex > 0 and aircraft.passengers[seatIndex] == ply then
                aircraft.passengers[seatIndex] = nil
            end
        end
    end
end)

-- Emergency USE key exit fallback for WAC aircraft
hook.Add("KeyPress", "Rareload_WAC_Emergency_Exit", function(ply, key)
    if key == IN_USE and IsValid(ply) and ply:InVehicle() then
        local veh = ply:GetVehicle()
        if IsValid(veh) then
            local aircraft = veh.wac_aircraft or (veh.GetNWEntity and veh:GetNWEntity("wac_aircraft")) or (veh.GetParent and veh:GetParent())
            if IsValid(aircraft) and string.find(string.lower(aircraft:GetClass() or ""), "^wac_") then
                ply._wac_last_use_exit = ply._wac_last_use_exit or 0
                if CurTime() - ply._wac_last_use_exit > 0.4 then
                    ply._wac_last_use_exit = CurTime()
                    ply:ExitVehicle()
                end
            end
        end
    end
end)

hook.Add("OnEntityCreated", "Rareload_WAC_Patch_New_Entity", function(ent)
    if IsValid(ent) and string.find(string.lower(ent:GetClass() or ""), "^wac_") then
        timer.Simple(0, function()
            if IsValid(ent) then PatchWACEntity(ent) end
        end)
    end
end)
