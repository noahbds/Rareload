-- ============================================================================
-- WAC AIRCRAFT COMPATIBILITY
-- ============================================================================

RARELOAD = RARELOAD or {}
if RARELOAD.WACCompat then return RARELOAD.WACCompat end

local WAC = {}
RARELOAD.WACCompat = WAC

local function IsWACClass(class)
    return string.find(string.lower(class or ""), "^wac_") ~= nil
end
WAC.IsWACClass = IsWACClass

function WAC.ResolveAircraft(ent)
    if not IsValid(ent) then return NULL end
    local aircraft = ent.wac_aircraft
        or (isfunction(ent.GetNWEntity) and ent:GetNWEntity("wac_aircraft"))
        or (isfunction(ent.GetParent) and ent:GetParent())
    return IsValid(aircraft) and aircraft or NULL
end

function WAC.ResolveSeatIndex(aircraft, seat)
    if not IsValid(seat) then return 1 end

    local idx = seat.wac_seatinfo
        or seat.wac_passenger_id
        or (isfunction(seat.GetNWInt) and seat:GetNWInt("wac_passenger_id", 0))
        or 0
    idx = tonumber(idx) or 0

    if idx <= 0 and IsValid(aircraft) and istable(aircraft.seats) then
        for i, s in pairs(aircraft.seats) do
            if s == seat then
                idx = tonumber(i) or 1
                break
            end
        end
    end

    if idx <= 0 then idx = 1 end
    return idx
end

function WAC.PatchEntity(ent)
    if not IsValid(ent) or not IsWACClass(ent:GetClass()) then return end
    if not isfunction(ent.receiveInput) or ent._Rareload_PatchedReceiveInput then return end

    ent._Rareload_PatchedReceiveInput = true
    local origReceiveInput = ent.receiveInput

    ent.receiveInput = function(self, name, value, seatIndex)
        name = tostring(name or "")
        value = tonumber(value) or 1
        seatIndex = tonumber(seatIndex) or 1

        self.passengers = self.passengers or {}
        local passenger = self.passengers[seatIndex]
        if not IsValid(passenger) and IsValid(self.passengers[1]) then
            passenger = self.passengers[1]
        end

        -- Pressing Exit must always let the player out.
        if string.lower(name) == "exit" and value > 0.5 and IsValid(passenger) then
            passenger:ExitVehicle()
            return
        end

        local ok = pcall(origReceiveInput, self, name, value, seatIndex)
        if not ok and string.lower(name) == "exit" and value > 0.5 and IsValid(passenger) then
            passenger:ExitVehicle()
        end
    end
end

function WAC.BindPassenger(aircraft, seat, ply)
    if not (IsValid(aircraft) and IsValid(seat) and IsValid(ply)) then return 1 end

    WAC.PatchEntity(aircraft)

    ply.wac = ply.wac or {}
    if ply.wac.mouseInput == nil then ply.wac.mouseInput = false end
    ply.wac.lastEnter = ply.wac.lastEnter or CurTime()
    if isfunction(aircraft.updateSeats) then pcall(aircraft.updateSeats, aircraft) end

    return WAC.ResolveSeatIndex(aircraft, seat)
end

-- ============================================================================
-- LOAD-ORDER-SAFE wac_air_input WRAPPER
-- ============================================================================

local ourInputFn
local origWACAirInput

local function installInputWrapper()
    local current = concommand.GetTable() and concommand.GetTable()["wac_air_input"]
    if isfunction(current) and current ~= ourInputFn then
        origWACAirInput = current -- WAC's genuine handler
    end
    concommand.Add("wac_air_input", ourInputFn)
end

ourInputFn = function(p, c, a)
    if IsValid(p) and isfunction(p.GetVehicle) then
        local aircraft = WAC.ResolveAircraft(p:GetVehicle())
        if IsValid(aircraft) and aircraft.SpawnedByRareload then
            WAC.PatchEntity(aircraft)
        end
    end

    if isfunction(origWACAirInput) then
        return origWACAirInput(p, c, a)
    end
end

installInputWrapper()
hook.Add("InitPostEntity", "Rareload_WAC_InstallInputWrapper", installInputWrapper)

-- ============================================================================
-- FAILSAFE HOOKS (restored aircraft only)
-- ============================================================================

hook.Add("PlayerEnteredVehicle", "Rareload_WAC_Server_Enter_Failsafe", function(ply, veh)
    if not IsValid(ply) or not IsValid(veh) then return end

    local aircraft = WAC.ResolveAircraft(veh)
    if IsValid(aircraft) and aircraft.SpawnedByRareload and IsWACClass(aircraft:GetClass()) then
        WAC.BindPassenger(aircraft, veh, ply)
    end
end)

hook.Add("PlayerLeaveVehicle", "Rareload_WAC_Server_Leave_Failsafe", function(ply, veh)
    if IsValid(ply) then
        ply.wac = ply.wac or {}
        ply.wac.mouseInput = false
    end
    if IsValid(veh) and isfunction(veh.GetNWEntity) then
        local aircraft = veh:GetNWEntity("wac_aircraft")
        if IsValid(aircraft) and istable(aircraft.passengers) then
            local seatIndex = veh:GetNWInt("wac_passenger_id", 0)
            if seatIndex > 0 and aircraft.passengers[seatIndex] == ply then
                aircraft.passengers[seatIndex] = nil
            end
        end
    end
end)

hook.Add("KeyPress", "Rareload_WAC_Emergency_Exit", function(ply, key)
    if key ~= IN_USE or not IsValid(ply) or not ply:InVehicle() then return end

    local aircraft = WAC.ResolveAircraft(ply:GetVehicle())
    if IsValid(aircraft) and aircraft.SpawnedByRareload and IsWACClass(aircraft:GetClass()) then
        ply._wac_last_use_exit = ply._wac_last_use_exit or 0
        if CurTime() - ply._wac_last_use_exit > 0.4 then
            ply._wac_last_use_exit = CurTime()
            ply:ExitVehicle()
        end
    end
end)

return WAC
