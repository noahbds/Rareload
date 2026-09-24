-- Vehicle base adapters, seats and the WAC fixes (REWRITE_PLAN.md §20, ported from v4). Each adapter
-- captures the runtime state its base wipes after a duplicator paste (L14, L15) and says when a
-- pasted vehicle is ready for it. Every call into a base is pcall-guarded: a renamed method must
-- never break a save or a restore.

RARELOAD.Vehicles = RARELOAD.Vehicles or {}
local Vehicles = RARELOAD.Vehicles
Vehicles.adapters = Vehicles.adapters or {}

-- adapter = { id, priority, matches(ent), isReady?(ent), readyTimeout?, selfStabilizes?,
--             captureRoot?(ent), applyRoot?(ent, t), captureComponents?(ent), applyComponents?(ent, list),
--             onSeatEnter?(ent, seat, ply) }
function Vehicles.Adapter(adapter)
    Vehicles.adapters[adapter.id] = adapter
end

function Vehicles.AdapterFor(ent)
    local best
    for _, a in pairs(Vehicles.adapters) do
        local ok, match = pcall(a.matches, ent)
        if ok and match and (not best or a.priority > best.priority) then best = a end
    end
    return best
end

-- Guarded accessors ---------------------------------------------------------------------------------

local function get(ent, method, check)
    if not isfunction(ent[method]) then return nil end
    local ok, v = pcall(ent[method], ent)
    if ok and (not check or check(v)) then return v end
end

local function set(ent, method, value)
    if value ~= nil and isfunction(ent[method]) then pcall(ent[method], ent, value) end
end

local function physReady(ent)
    return IsValid(ent:GetPhysicsObject())
end

local function captureCosmetic(ent, t)
    local c = get(ent, "GetColor", istable)
    if c then t.color = { c.r, c.g, c.b, c.a } end
    t.skin = get(ent, "GetSkin", isnumber)
    local groups = {}
    for _, g in ipairs(ent:GetBodyGroups() or {}) do
        local v = ent:GetBodygroup(g.id)
        if v ~= 0 then groups[tostring(g.id)] = v end
    end
    if next(groups) then t.bodygroups = groups end
end

local function applyCosmetic(ent, t, colorSetter)
    if istable(t.color) then
        set(ent, colorSetter or "SetColor", Color(t.color[1], t.color[2], t.color[3], t.color[4]))
        ent:SetRenderMode(t.color[4] < 255 and RENDERMODE_TRANSALPHA or RENDERMODE_NORMAL)
    end
    set(ent, "SetSkin", t.skin)
    for id, v in pairs(t.bodygroups or {}) do ent:SetBodygroup(tonumber(id), v) end
end

-- Seats ---------------------------------------------------------------------------------------------

local Seats = {}
Vehicles.Seats = Seats

local function isSeat(s)
    return IsValid(s) and s:IsVehicle()
end

function Seats.All(veh)
    local seats, seen = {}, {}
    local function add(s)
        if isSeat(s) and not seen[s] then
            seen[s] = true
            seats[#seats + 1] = s
        end
    end
    add(get(veh, "GetDriverSeat"))
    add(get(veh, "GetGunnerSeat"))
    for _, s in pairs(get(veh, "GetPassengerSeats", istable) or {}) do add(s) end
    for _, field in ipairs({ "DriverSeat", "GunnerSeat" }) do add(veh[field]) end
    for _, field in ipairs({ "pSeats", "PassengerSeats", "seats", "Seats" }) do
        for _, s in pairs(istable(veh[field]) and veh[field] or {}) do add(s) end
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
        for _, s in ipairs(seats) do
            if podIndex(s) == desc.pod then return s end
        end
    end
    local target = RARELOAD.Util.ToVector(desc.pos)
    local best, bestDist
    for _, s in ipairs(seats) do
        local d = target and veh:WorldToLocal(s:GetPos()):DistToSqr(target) or math.huge
        if not bestDist or d < bestDist or (d == bestDist and s:GetClass() == desc.class) then best, bestDist = s, d end
    end
    return best
end

-- Base adapters -------------------------------------------------------------------------------------

Vehicles.Adapter({
    id = "source",
    priority = 0,
    matches = function(ent) return ent:IsVehicle() end,
    isReady = function(ent) return physReady(ent) and (not ent.IsValidVehicle or ent:IsValidVehicle()) end,   -- G69
    captureRoot = function(ent)
        local t = { health = get(ent, "Health", isnumber), maxHealth = get(ent, "GetMaxHealth", isnumber) }
        captureCosmetic(ent, t)
        return t
    end,
    applyRoot = function(ent, t)
        set(ent, "SetMaxHealth", t.maxHealth)
        set(ent, "SetHealth", t.health)
        applyCosmetic(ent, t)
    end,
})

Vehicles.Adapter({
    id = "simfphys",
    priority = 20,
    selfStabilizes = true,
    matches = function(ent) return ent.IsSimfphyscar == true end,
    isReady = physReady,
    captureRoot = function(ent)
        local t = {
            active = get(ent, "GetActive", isbool), lights = get(ent, "GetLightsEnabled", isbool),
            handbrake = get(ent, "GetHandbrake", isbool), health = get(ent, "GetCurHealth", isnumber),
            maxHealth = get(ent, "GetMaxHealth", isnumber), fuel = get(ent, "GetFuel", isnumber),
            maxFuel = get(ent, "GetMaxFuel", isnumber), fuelType = get(ent, "GetFuelType"),
        }
        captureCosmetic(ent, t)
        return t
    end,
    applyRoot = function(ent, t)
        set(ent, "SetMaxHealth", t.maxHealth)
        set(ent, "SetCurHealth", t.health)
        set(ent, "SetMaxFuel", t.maxFuel)
        set(ent, "SetFuelType", t.fuelType)
        set(ent, "SetFuel", t.fuel)
        set(ent, "SetLightsEnabled", t.lights)
        set(ent, "SetHandbrake", t.handbrake)
        applyCosmetic(ent, t, isfunction(ent.SetColors) and "SetColors" or "SetColor")
        set(ent, "SetActive", t.active)   -- last: it starts the drivetrain
    end,
})

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

Vehicles.Adapter({
    id = "lvs",
    priority = 20,
    selfStabilizes = true,
    matches = function(ent) return ent.LVS == true end,
    isReady = function(ent)
        local ready = get(ent, "GetlvsReady", isbool)
        if ready == nil then return physReady(ent) end
        return ready
    end,
    captureRoot = function(ent)
        local t = {
            engineActive = get(ent, "GetEngineActive", isbool), active = get(ent, "GetActive", isbool),
            hp = get(ent, "GetHP", isnumber), maxHp = get(ent, "GetMaxHP", isnumber),
            damaged = get(ent, "GetDamaged", isbool), ambientLight = get(ent, "GetAmbientLight"),
        }
        captureCosmetic(ent, t)
        return t
    end,
    applyRoot = function(ent, t)
        set(ent, "SetMaxHP", t.maxHp)
        set(ent, "SetHP", t.hp)
        set(ent, "SetDamaged", t.damaged)
        set(ent, "SetAmbientLight", t.ambientLight)
        set(ent, "SetEngineActive", t.engineActive)
        set(ent, "SetActive", t.active)
        applyCosmetic(ent, t)
    end,
    captureComponents = function(ent)
        local out = {}
        for _, c in ipairs(lvsComponents(ent)) do
            local lp = ent:WorldToLocal(c:GetPos())
            out[#out + 1] = { class = c:GetClass(), pos = { lp.x, lp.y, lp.z }, hp = get(c, "GetHP", isnumber),
                maxHp = get(c, "GetMaxHP", isnumber) }
        end
        return #out > 0 and out or nil
    end,
    applyComponents = function(ent, list)
        local live, used = lvsComponents(ent), {}
        for _, saved in ipairs(list) do
            local target, best, bestDist = RARELOAD.Util.ToVector(saved.pos), nil, nil
            for _, c in ipairs(live) do
                if not used[c] and c:GetClass() == saved.class and target then
                    local d = ent:WorldToLocal(c:GetPos()):DistToSqr(target)
                    if not bestDist or d < bestDist then best, bestDist = c, d end
                end
            end
            if best then
                used[best] = true
                set(best, "SetMaxHP", saved.maxHp)
                set(best, "SetHP", saved.hp)
            end
        end
    end,
})

-- Glide restores its tuning variables itself; only the runtime state it filters out is re-applied.
Vehicles.Adapter({
    id = "glide",
    priority = 20,
    selfStabilizes = true,
    matches = function(ent) return ent.IsGlideVehicle == true end,
    isReady = physReady,
    captureRoot = function(ent)
        local ang = get(ent, "GetTurretAngle", isangle)
        local t = {
            engineState = get(ent, "GetEngineState", isnumber), chassisHealth = get(ent, "GetChassisHealth", isnumber),
            engineHealth = get(ent, "GetEngineHealth", isnumber), tireHealth = get(ent, "GetTireHealth", isnumber),
            isOnFire = get(ent, "GetIsOnFire", isbool), gear = get(ent, "GetGear", isnumber),
            headlight = get(ent, "GetHeadlightState", isnumber), siren = get(ent, "GetSirenState", isnumber),
            turnSignal = get(ent, "GetTurnSignalState", isnumber), lockState = get(ent, "GetLockState", isnumber),
            isLocked = get(ent, "GetIsLocked", isbool), weaponIndex = get(ent, "GetWeaponIndex", isnumber),
            turret = ang and RARELOAD.Util.Ang(ang),
        }
        captureCosmetic(ent, t)
        t.color = nil   -- Glide's paint is tuning data it restores itself
        return t
    end,
    applyRoot = function(ent, t)
        set(ent, "SetChassisHealth", t.chassisHealth)
        set(ent, "SetEngineHealth", t.engineHealth)
        set(ent, "SetTireHealth", t.tireHealth)
        set(ent, "SetIsOnFire", t.isOnFire)
        set(ent, "SetGear", t.gear)
        set(ent, "SetHeadlightState", t.headlight)
        set(ent, "SetSirenState", t.siren)
        set(ent, "SetTurnSignalState", t.turnSignal)
        set(ent, "SetLockState", t.lockState)
        set(ent, "SetIsLocked", t.isLocked)
        set(ent, "SetTurretAngle", RARELOAD.Util.ToAngle(t.turret))
        set(ent, "SetWeaponIndex", t.weaponIndex)
        applyCosmetic(ent, t)
        set(ent, "SetEngineState", t.engineState)   -- last: it drives lights and sound
    end,
})

Vehicles.Adapter({
    id = "lfs",
    priority = 20,
    selfStabilizes = true,
    matches = function(ent) return ent.LFS == true end,
    isReady = physReady,
    captureRoot = function(ent)
        local t = {
            active = get(ent, "GetActive", isbool), engineActive = get(ent, "GetEngineActive", isbool),
            isLocked = get(ent, "GetIsLocked", isbool), hp = get(ent, "GetHP", isnumber),
            shield = get(ent, "GetShield", isnumber), lgear = get(ent, "GetLGear", isnumber),
            rgear = get(ent, "GetRGear", isnumber),
        }
        captureCosmetic(ent, t)
        return t
    end,
    applyRoot = function(ent, t)
        set(ent, "SetHP", t.hp)
        set(ent, "SetShield", t.shield)
        set(ent, "SetLGear", t.lgear)
        set(ent, "SetRGear", t.rgear)
        set(ent, "SetIsLocked", t.isLocked)
        set(ent, "SetEngineActive", t.engineActive)
        set(ent, "SetActive", t.active)
        applyCosmetic(ent, t)
    end,
})

-- WAC -------------------------------------------------------------------------------------------------
-- Restored WAC aircraft need their input handler wrapped so "Exit" always works, and passengers
-- need binding when they are put back in a seat (from v4's sv_rareload_wac_compat).

local function isWAC(ent)
    return IsValid(ent) and string.StartsWith(string.lower(ent:GetClass()), "wac_")
end

local function aircraftOf(seat)
    local a = seat.wac_aircraft or seat:GetNWEntity("wac_aircraft")
    if not IsValid(a) then a = seat:GetParent() end
    return IsValid(a) and a or nil
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

Vehicles.Adapter({
    id = "wac",
    priority = 30,
    selfStabilizes = true,
    readyTimeout = 5,
    matches = isWAC,
    isReady = function(ent) return isfunction(ent.receiveInput) end,
    captureRoot = function(ent)
        local t = { health = get(ent, "Health", isnumber), maxHealth = get(ent, "GetMaxHealth", isnumber) }
        captureCosmetic(ent, t)
        return t
    end,
    applyRoot = function(ent, t)
        set(ent, "SetMaxHealth", t.maxHealth)
        set(ent, "SetHealth", t.health)
        applyCosmetic(ent, t)
        patchWAC(ent)
    end,
    onSeatEnter = function(ent, _, ply)
        patchWAC(ent)
        ply.wac = ply.wac or {}
        if ply.wac.mouseInput == nil then ply.wac.mouseInput = false end
        -- WAC sets this only when entering with Use, and compares it to CurTime() on every input.
        ply.wac.lastEnter = ply.wac.lastEnter or CurTime()
        if isfunction(ent.updateSeats) then pcall(ent.updateSeats, ent) end
    end,
})

hook.Add("PlayerEnteredVehicle", "Rareload.WAC.Bind", function(ply, seat)
    local aircraft = aircraftOf(seat)
    if aircraft and aircraft.RareloadID and isWAC(aircraft) then Vehicles.adapters.wac.onSeatEnter(aircraft, seat, ply) end
end)

hook.Add("PlayerLeaveVehicle", "Rareload.WAC.Leave", function(ply)
    if ply.wac then ply.wac.mouseInput = false end
end)
