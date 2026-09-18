-- ============================================================================
-- Base-agnostic seat enumeration, descriptor building, and matching.
-- ============================================================================

RARELOAD = RARELOAD or {}
if RARELOAD.VehicleSeats then return RARELOAD.VehicleSeats end

local Seats = {}
RARELOAD.VehicleSeats = Seats

local SINGLE_SEAT_METHODS = { "GetDriverSeat", "GetGunnerSeat" }
local TABLE_SEAT_METHODS  = { "GetPassengerSeats" }
local SINGLE_SEAT_PROPS   = { "DriverSeat", "GunnerSeat" }
local TABLE_SEAT_PROPS    = { "pSeats", "PassengerSeats", "seats", "Seats" }
local SEAT_MATCH_TOL_SQR  = 2304 -- 48^2

-- ---------------------------------------------------------------------------
-- Validation & enumeration
-- ---------------------------------------------------------------------------

function Seats.IsSeat(seat, requireEmpty)
    if not IsValid(seat) then return false end
    if not isfunction(seat.IsVehicle) or not seat:IsVehicle() then return false end
    if requireEmpty and isfunction(seat.GetDriver) and IsValid(seat:GetDriver()) then return false end
    return true
end

--- Enumerate every seat entity belonging to a (root) vehicle, de-duplicated.
function Seats.Enumerate(veh)
    local seats, seen = {}, {}
    local function add(s)
        if Seats.IsSeat(s, false) and not seen[s] then
            seen[s] = true
            seats[#seats + 1] = s
        end
    end

    for _, method in ipairs(SINGLE_SEAT_METHODS) do
        if isfunction(veh[method]) then
            local ok, ds = pcall(veh[method], veh)
            if ok and ds then add(ds) end
        end
    end
    for _, prop in ipairs(SINGLE_SEAT_PROPS) do
        if veh[prop] then add(veh[prop]) end
    end
    for _, method in ipairs(TABLE_SEAT_METHODS) do
        if isfunction(veh[method]) then
            local ok, ps = pcall(veh[method], veh)
            if ok and istable(ps) then
                for _, s in pairs(ps) do if s then add(s) end end
            end
        end
    end
    for _, prop in ipairs(TABLE_SEAT_PROPS) do
        if istable(veh[prop]) then
            for _, s in pairs(veh[prop]) do if s then add(s) end end
        end
    end
    if isfunction(veh.GetChildren) then
        for _, child in ipairs(veh:GetChildren() or {}) do
            add(child)
            if isfunction(child.GetChildren) then
                for _, subChild in ipairs(child:GetChildren() or {}) do add(subChild) end
            end
        end
    end
    add(veh)
    return seats
end

function Seats.GetFreeSeat(veh)
    if not IsValid(veh) then return nil end
    for _, s in ipairs(Seats.Enumerate(veh)) do
        if Seats.IsSeat(s, true) then return s end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Descriptors (save side)
-- ---------------------------------------------------------------------------

local function readPodIndex(seat)
    if isfunction(seat.lvsGetPodIndex) then
        local ok, idx = pcall(seat.lvsGetPodIndex, seat)
        if ok and isnumber(idx) and idx >= 0 then return idx end
    end
    if isfunction(seat.GetNWInt) then
        local idx = seat:GetNWInt("pPodIndex", -1)
        if idx and idx >= 0 then return idx end
    end
    return nil
end

--- Build a serializable descriptor for one seat, relative to root.
function Seats.BuildDescriptor(root, seat)
    if not IsValid(seat) then return nil end
    local info = { class = seat:GetClass() }

    local podIndex = readPodIndex(seat)
    if podIndex then info.podIndex = podIndex end

    if IsValid(root) then
        local lp = root:WorldToLocal(seat:GetPos())
        info.localPos = { x = lp.x, y = lp.y, z = lp.z }
        if isfunction(root.GetDriverSeat) then
            local ok, ds = pcall(root.GetDriverSeat, root)
            if ok and ds == seat then info.isDriver = true end
        end
    end
    if root == seat then info.isDriver = true end

    return info
end

-- ---------------------------------------------------------------------------
-- Matching (restore side) -> seat, isExact
-- ---------------------------------------------------------------------------

function Seats.Resolve(veh, seatInfo)
    if not IsValid(veh) then return nil, false end
    if not istable(seatInfo) then return Seats.GetFreeSeat(veh), false end

    -- 1. Direct LVS pod-index call.
    if seatInfo.podIndex and isfunction(veh.GetPassengerSeat) then
        local ok, seat = pcall(veh.GetPassengerSeat, veh, seatInfo.podIndex)
        if ok and Seats.IsSeat(seat, false) then return seat, true end
    end

    local seats = Seats.Enumerate(veh)

    -- 2. Networked / accessor pod-index match.
    if seatInfo.podIndex then
        for _, s in ipairs(seats) do
            if readPodIndex(s) == seatInfo.podIndex then return s, true end
        end
    end

    -- 3. Nearest local-position match.
    if istable(seatInfo.localPos) then
        local target = Vector(seatInfo.localPos.x or 0, seatInfo.localPos.y or 0, seatInfo.localPos.z or 0)
        local best, bestDist
        for _, s in ipairs(seats) do
            local d = veh:WorldToLocal(s:GetPos()):DistToSqr(target)
            if not bestDist or d < bestDist then bestDist, best = d, s end
        end
        if IsValid(best) then return best, (bestDist ~= nil and bestDist <= SEAT_MATCH_TOL_SQR) end
    end

    -- 4. Class match.
    if seatInfo.class then
        for _, s in ipairs(seats) do
            if s:GetClass() == seatInfo.class then return s, false end
        end
    end

    return Seats.GetFreeSeat(veh), false
end

return Seats
