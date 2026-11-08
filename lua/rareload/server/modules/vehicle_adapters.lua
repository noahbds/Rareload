-- Vehicle base adapters, seats and the WAC fixes. Each adapter
-- captures the runtime state its base wipes after a duplicator paste (L14, L15) and says when a
-- pasted vehicle is ready for it. Every call into a base is pcall-guarded: a renamed method must
-- never break a save or a restore.

RARELOAD.Vehicles = RARELOAD.Vehicles or {}
local Vehicles = RARELOAD.Vehicles
Vehicles.adapters = Vehicles.adapters or {}

-- adapter = { id, priority, matches(ent), isReady?(ent), readyTimeout?, selfStabilizes?,
--             captureRoot?(ent), applyRoot?(ent, t), captureComponents?(ent), applyComponents?(ent, list),
--             onSeatEnter?(ent, seat, ply) }
-- Instead of captureRoot/applyRoot, an adapter can list the runtime values its base wipes (see
-- rootFromProps below): props = { { key, getter, setter, check?, toSave?, fromSave? } } in the order
-- they are set back, lastProps = the ones set after the colours (they start engines, lights, sound),
-- colorSetter?(ent) = the method that sets the colour, noPaint? = the base restores its paint itself,
-- afterApply?(ent, t).
function Vehicles.Adapter(adapter)
    Vehicles.adapters[adapter.id] = adapter
end

function Vehicles.AdapterFor(ent)
    local best
    for _, adapter in pairs(Vehicles.adapters) do
        local ok, match = pcall(adapter.matches, ent)
        if ok and match and (not best or adapter.priority > best.priority) then best = adapter end
    end
    return best
end

-- Guarded accessors ---------------------------------------------------------------------------------

local function get(ent, method, check)
    if not isfunction(ent[method]) then return nil end
    local ok, value = pcall(ent[method], ent)
    if ok and (not check or check(value)) then return value end
end

local function set(ent, method, value)
    if value ~= nil and isfunction(ent[method]) then pcall(ent[method], ent, value) end
end

local function physReady(ent)
    return IsValid(ent:GetPhysicsObject())
end

local function captureCosmetic(ent, state)
    local color = get(ent, "GetColor", istable)
    if color then state.color = { color.r, color.g, color.b, color.a } end
    state.skin = get(ent, "GetSkin", isnumber)
    local groups = {}
    for _, bodygroup in ipairs(ent:GetBodyGroups() or {}) do
        local value = ent:GetBodygroup(bodygroup.id)
        if value ~= 0 then groups[tostring(bodygroup.id)] = value end
    end
    if next(groups) then state.bodygroups = groups end
end

local function applyCosmetic(ent, state, colorSetter)
    if istable(state.color) then
        set(ent, colorSetter or "SetColor", Color(state.color[1], state.color[2], state.color[3], state.color[4]))
        ent:SetRenderMode(state.color[4] < 255 and RENDERMODE_TRANSALPHA or RENDERMODE_NORMAL)
    end
    set(ent, "SetSkin", state.skin)
    for id, value in pairs(state.bodygroups or {}) do ent:SetBodygroup(tonumber(id), value) end
end

local function captureProps(ent, state, props)
    for _, prop in ipairs(props or {}) do
        local value = get(ent, prop[2], prop[4])
        if value ~= nil and prop[5] then value = prop[5](value) end
        state[prop[1]] = value
    end
end

local function applyProps(ent, state, props)
    for _, prop in ipairs(props or {}) do
        local value = state[prop[1]]
        if value ~= nil and prop[6] then value = prop[6](value) end
        set(ent, prop[3], value)
    end
end

-- captureRoot and applyRoot made from an adapter's property lists (Vehicles.Adapter).
local function rootFromProps(adapter)
    adapter.captureRoot = function(ent)
        local state = {}
        captureProps(ent, state, adapter.props)
        captureProps(ent, state, adapter.lastProps)
        captureCosmetic(ent, state)
        if adapter.noPaint then state.color = nil end
        return state
    end
    adapter.applyRoot = function(ent, state)
        applyProps(ent, state, adapter.props)
        applyCosmetic(ent, state, adapter.colorSetter and adapter.colorSetter(ent))
        applyProps(ent, state, adapter.lastProps)
        if adapter.afterApply then adapter.afterApply(ent, state) end
    end
    return adapter
end

-- Seats ---------------------------------------------------------------------------------------------

local Seats = {}
Vehicles.Seats = Seats

local function isSeat(seat)
    return IsValid(seat) and seat:IsVehicle()
end

function Seats.All(veh)
    local seats, seen = {}, {}
    local function add(seat)
        if isSeat(seat) and not seen[seat] then
            seen[seat] = true
            seats[#seats + 1] = seat
        end
    end
    add(get(veh, "GetDriverSeat"))
    add(get(veh, "GetGunnerSeat"))
    for _, seat in pairs(get(veh, "GetPassengerSeats", istable) or {}) do add(seat) end
    for _, field in ipairs({ "DriverSeat", "GunnerSeat" }) do add(veh[field]) end
    for _, field in ipairs({ "pSeats", "PassengerSeats", "seats", "Seats" }) do
        for _, seat in pairs(istable(veh[field]) and veh[field] or {}) do add(seat) end
    end
    for _, child in ipairs(veh:GetChildren()) do
        add(child)
        for _, sub in ipairs(child:GetChildren()) do add(sub) end
    end
    add(veh)
    return seats
end

local function podIndex(seat)
    local idx = get(seat, "lvsGetPodIndex", isnumber) or seat:GetNWInt("pPodIndex", -1)
    return idx >= 0 and idx or nil
end

-- Where `ply` sits in `veh`, relative to the vehicle, so the same seat can be found after a paste.
function Seats.Describe(veh, seat)
    local lp = veh:WorldToLocal(seat:GetPos())
    return { class = seat:GetClass(), pod = podIndex(seat), pos = { lp.x, lp.y, lp.z } }
end

-- The seat matching a description: LVS pod index first, then the closest position, then the class.
function Seats.Find(veh, desc)
    local seats = Seats.All(veh)
    if desc.pod then
        if isfunction(veh.GetPassengerSeat) then
            local ok, seat = pcall(veh.GetPassengerSeat, veh, desc.pod)
            if ok and isSeat(seat) then return seat end
        end
        for _, seat in ipairs(seats) do
            if podIndex(seat) == desc.pod then return seat end
        end
    end
    local target = RARELOAD.Util.ToVector(desc.pos)
    local best, bestDist
    for _, seat in ipairs(seats) do
        local dist = target and veh:WorldToLocal(seat:GetPos()):DistToSqr(target) or math.huge
        if not bestDist or dist < bestDist or (dist == bestDist and seat:GetClass() == desc.class) then
            best, bestDist = seat, dist
        end
    end
    return best
end

-- Base adapters -------------------------------------------------------------------------------------

Vehicles.Adapter(rootFromProps({
    id = "source",
    priority = 0,
    matches = function(ent) return ent:IsVehicle() end,
    isReady = function(ent) return physReady(ent) and (not ent.IsValidVehicle or ent:IsValidVehicle()) end, -- G69
    props = {
        { "maxHealth", "GetMaxHealth", "SetMaxHealth", isnumber }, { "health", "Health", "SetHealth", isnumber },
    },
}))

Vehicles.Adapter(rootFromProps({
    id = "simfphys",
    priority = 20,
    selfStabilizes = true,
    matches = function(ent) return ent.IsSimfphyscar == true end,
    isReady = physReady,
    props = {
        { "maxHealth", "GetMaxHealth", "SetMaxHealth", isnumber },
        { "health", "GetCurHealth", "SetCurHealth", isnumber },
        { "maxFuel", "GetMaxFuel", "SetMaxFuel", isnumber }, { "fuelType", "GetFuelType", "SetFuelType" },
        { "fuel", "GetFuel", "SetFuel", isnumber }, { "lights", "GetLightsEnabled", "SetLightsEnabled", isbool },
        { "handbrake", "GetHandbrake", "SetHandbrake", isbool },
    },
    lastProps = { { "active", "GetActive", "SetActive", isbool } }, -- it starts the drivetrain
    colorSetter = function(ent) return isfunction(ent.SetColors) and "SetColors" or "SetColor" end,
}))

-- LVS keeps HP on engine, rotor and ammorack sub-entities (L15).
local function lvsComponents(root)
    local out, seen = {}, {}
    local function walk(ent, depth)
        if depth > 4 then return end
        for _, child in ipairs(ent:GetChildren()) do
            if not seen[child] then
                seen[child] = true
                if isfunction(child.GetHP) and isfunction(child.SetHP) then out[#out + 1] = child end
                walk(child, depth + 1)
            end
        end
    end
    walk(root, 0)
    return out
end

Vehicles.Adapter(rootFromProps({
    id = "lvs",
    priority = 20,
    selfStabilizes = true,
    matches = function(ent) return ent.LVS == true end,
    isReady = function(ent)
        local ready = get(ent, "GetlvsReady", isbool)
        if ready == nil then return physReady(ent) end
        return ready
    end,
    props = {
        { "maxHp", "GetMaxHP", "SetMaxHP", isnumber }, { "hp", "GetHP", "SetHP", isnumber },
        { "damaged", "GetDamaged", "SetDamaged", isbool }, { "ambientLight", "GetAmbientLight", "SetAmbientLight" },
        { "engineActive", "GetEngineActive", "SetEngineActive", isbool },
            { "active", "GetActive", "SetActive", isbool },
    },
    captureComponents = function(ent)
        local out = {}
        for _, component in ipairs(lvsComponents(ent)) do
            local lp = ent:WorldToLocal(component:GetPos())
            out[#out + 1] = {
                class = component:GetClass(),
                pos = { lp.x, lp.y, lp.z },
                hp = get(component, "GetHP", isnumber),
                maxHp = get(component, "GetMaxHP", isnumber)
            }
        end
        return #out > 0 and out or nil
    end,
    applyComponents = function(ent, list)
        local live, used = lvsComponents(ent), {}
        for _, saved in ipairs(list) do
            local target, best, bestDist = RARELOAD.Util.ToVector(saved.pos), nil, nil
            for _, component in ipairs(live) do
                if not used[component] and component:GetClass() == saved.class and target then
                    local dist = ent:WorldToLocal(component:GetPos()):DistToSqr(target)
                    if not bestDist or dist < bestDist then best, bestDist = component, dist end
                end
            end
            if best then
                used[best] = true
                set(best, "SetMaxHP", saved.maxHp)
                set(best, "SetHP", saved.hp)
            end
        end
    end,
}))

-- Glide restores its tuning variables itself; only the runtime state it filters out is re-applied.
Vehicles.Adapter(rootFromProps({
    id = "glide",
    priority = 20,
    selfStabilizes = true,
    matches = function(ent) return ent.IsGlideVehicle == true end,
    isReady = physReady,
    props = {
        { "chassisHealth", "GetChassisHealth", "SetChassisHealth", isnumber },
        { "engineHealth", "GetEngineHealth", "SetEngineHealth", isnumber },
        { "tireHealth", "GetTireHealth", "SetTireHealth", isnumber },
        { "isOnFire", "GetIsOnFire", "SetIsOnFire", isbool }, { "gear", "GetGear", "SetGear", isnumber },
        { "headlight", "GetHeadlightState", "SetHeadlightState", isnumber },
        { "siren", "GetSirenState", "SetSirenState", isnumber },
        { "turnSignal", "GetTurnSignalState", "SetTurnSignalState", isnumber },
        { "lockState", "GetLockState", "SetLockState", isnumber }, { "isLocked", "GetIsLocked", "SetIsLocked", isbool },
        { "turret", "GetTurretAngle", "SetTurretAngle", isangle, RARELOAD.Util.Ang, RARELOAD.Util.ToAngle },
        { "weaponIndex", "GetWeaponIndex", "SetWeaponIndex", isnumber },
    },
    lastProps = { { "engineState", "GetEngineState", "SetEngineState", isnumber } }, -- it drives lights and sound
    noPaint = true, -- Glide's paint is tuning data it restores itself
}))

Vehicles.Adapter(rootFromProps({
    id = "lfs",
    priority = 20,
    selfStabilizes = true,
    matches = function(ent) return ent.LFS == true end,
    isReady = physReady,
    props = {
        { "hp", "GetHP", "SetHP", isnumber }, { "shield", "GetShield", "SetShield", isnumber },
        { "lgear", "GetLGear", "SetLGear", isnumber }, { "rgear", "GetRGear", "SetRGear", isnumber },
        { "isLocked", "GetIsLocked", "SetIsLocked", isbool },
        { "engineActive", "GetEngineActive", "SetEngineActive", isbool },
            { "active", "GetActive", "SetActive", isbool },
    },
}))

-- WAC -------------------------------------------------------------------------------------------------
-- Restored WAC aircraft need their input handler wrapped so "Exit" always works, and passengers
-- need binding when they are put back in a seat (from v4's sv_rareload_wac_compat).

local function isWAC(ent)
    return IsValid(ent) and string.StartsWith(string.lower(ent:GetClass()), "wac_")
end

local function aircraftOf(seat)
    local aircraft = seat.wac_aircraft or seat:GetNWEntity("wac_aircraft")
    if not IsValid(aircraft) then aircraft = seat:GetParent() end
    return IsValid(aircraft) and aircraft or nil
end

-- Kept outside the entity's table: that table is saved with the aircraft, so a flag stored there
-- came back on the restored aircraft and it was never patched.
local patched = setmetatable({}, { __mode = "k" })

local function patchWAC(ent)
    if not isWAC(ent) or not isfunction(ent.receiveInput) or patched[ent] then return end
    patched[ent] = true
    local original = ent.receiveInput
    ent.receiveInput = function(self, name, value, seatIndex)
        seatIndex = tonumber(seatIndex) or 1
        self.passengers = self.passengers or {}
        local passenger = self.passengers[seatIndex] or self.passengers[1]
        local exiting = string.lower(tostring(name)) == "exit" and (tonumber(value) or 1) > 0.5
        if exiting and IsValid(passenger) then return passenger:ExitVehicle() end
        return original(self, name, value, seatIndex)
    end
end

Vehicles.Adapter(rootFromProps({
    id = "wac",
    priority = 30,
    selfStabilizes = true,
    readyTimeout = 5,
    matches = isWAC,
    isReady = function(ent) return isfunction(ent.receiveInput) end,
    props = {
        { "maxHealth", "GetMaxHealth", "SetMaxHealth", isnumber }, { "health", "Health", "SetHealth", isnumber },
    },
    afterApply = patchWAC,
    onSeatEnter = function(ent, _, ply)
        patchWAC(ent)
        ply.wac = ply.wac or {}
        if ply.wac.mouseInput == nil then ply.wac.mouseInput = false end
        -- WAC sets this only when entering with Use, and compares it to CurTime() on every input.
        ply.wac.lastEnter = ply.wac.lastEnter or CurTime()
        if isfunction(ent.updateSeats) then pcall(ent.updateSeats, ent) end
    end,
}))

hook.Add("PlayerEnteredVehicle", "Rareload.WAC.Bind", function(ply, seat)
    local aircraft = aircraftOf(seat)
    if aircraft and aircraft.RareloadID and isWAC(aircraft) then
        Vehicles.adapters.wac.onSeatEnter(aircraft, seat, ply)
    end
end)

hook.Add("PlayerLeaveVehicle", "Rareload.WAC.Leave", function(ply)
    if ply.wac then ply.wac.mouseInput = false end
end)
