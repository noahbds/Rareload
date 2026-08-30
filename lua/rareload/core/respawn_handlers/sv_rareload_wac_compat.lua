-- ============================================================================
-- WAC AIRCRAFT COMPATIBILITY
-- ============================================================================
-- WAC vehicles are fragile when re-spawned by the duplicator: their internal
-- numeric fields and passenger tables aren't fully rebuilt, so seating a player
-- (or the client's CalcView hooks) can throw nil-comparison errors and trap the
-- player. This module concentrates every WAC workaround in one place:
--   * PatchEntity      - null-guards a restored WAC entity + makes exit reliable
--   * ResolveAircraft  - find the aircraft entity from a seat/pod
--   * ResolveSeatIndex - find the WAC passenger index for a seat
--   * BindPassenger    - wire the passenger tables/networked vars before seating
-- It also installs the failsafe hooks and a load-order-safe wrapper around the
-- `wac_air_input` console command (previous versions hijacked it outright).

RARELOAD = RARELOAD or {}
if RARELOAD.WACCompat then return RARELOAD.WACCompat end

local WAC = {}
RARELOAD.WACCompat = WAC

local function IsWACClass(class)
    return string.find(string.lower(class or ""), "^wac_") ~= nil
end
WAC.IsWACClass = IsWACClass

-- Resolve the aircraft entity that owns a seat/pod (or the entity itself).
function WAC.ResolveAircraft(ent)
    if not IsValid(ent) then return NULL end
    local aircraft = ent.wac_aircraft
        or (isfunction(ent.GetNWEntity) and ent:GetNWEntity("wac_aircraft"))
        or (isfunction(ent.GetParent) and ent:GetParent())
    return IsValid(aircraft) and aircraft or NULL
end

-- Resolve the WAC passenger index for a seat, falling back to the aircraft's
-- seat table and finally to 1.
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

-- Guarantee the internal numeric fields WAC reads exist, and wrap receiveInput
-- so a stray nil can't crash it or trap a player who wants out. Idempotent.
function WAC.PatchEntity(ent)
    if not IsValid(ent) or not IsWACClass(ent:GetClass()) then return end

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
end

-- Wire the aircraft/seat/player passenger tables and networked vars so WAC's
-- input handling knows who is where. Returns the resolved seat index.
function WAC.BindPassenger(aircraft, seat, ply)
    if not (IsValid(aircraft) and IsValid(seat) and IsValid(ply)) then return 1 end

    WAC.PatchEntity(aircraft)
    local idx = WAC.ResolveSeatIndex(aircraft, seat)

    aircraft.passengers = aircraft.passengers or {}
    aircraft.passengers[idx] = ply
    if istable(aircraft.seats) and not aircraft.seats[idx] then
        aircraft.seats[idx] = seat
    end

    seat.wac_seatinfo = idx
    seat.wac_passenger_id = idx
    if isfunction(seat.SetNWInt) then seat:SetNWInt("wac_passenger_id", idx) end
    if isfunction(seat.SetNWEntity) then seat:SetNWEntity("wac_aircraft", aircraft) end

    if isfunction(ply.SetNWInt) then ply:SetNWInt("wac_passenger_id", idx) end
    if isfunction(ply.SetNWEntity) then ply:SetNWEntity("wac_aircraft", aircraft) end

    ply.wac = ply.wac or {}
    if ply.wac.mouseInput == nil then ply.wac.mouseInput = false end

    return idx
end

-- ============================================================================
-- LOAD-ORDER-SAFE wac_air_input WRAPPER
-- ============================================================================
-- Two addons can't both own a console command (last `concommand.Add` wins), so
-- previous versions replaced WAC's handler outright — which broke normal WAC
-- input whenever Rareload loaded first. Instead we capture WAC's real callback
-- (re-checking on InitPostEntity in case WAC loads after us) and always call
-- through to it, only patching restored aircraft on the way.

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
        -- Only touch aircraft Rareload restored; normal WAC vehicles are left to
        -- WAC entirely.
        if IsValid(aircraft) and aircraft.SpawnedByRareload then
            WAC.PatchEntity(aircraft)
        end
    end

    -- Hand off to WAC's own handler for the actual flight input.
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

-- Emergency USE-key exit for restored WAC aircraft (their normal exit can be
-- broken right after a duplicator paste).
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
