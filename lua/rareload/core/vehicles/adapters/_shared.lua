-- ============================================================================
-- Small pcall-guarded accessor helpers shared by the vehicle adapters. Every
-- getter returns nil on failure and every setter is a no-op on failure, so a
-- renamed/removed base method can never break a save or a restore.
-- ============================================================================

local H = {}

--- Call a getter method by name; return its value only if it passes `check`.
function H.get(ent, method, check)
    if not (IsValid(ent) and isfunction(ent[method])) then return nil end
    local ok, val = pcall(ent[method], ent)
    if not ok then return nil end
    if check and not check(val) then return nil end
    return val
end

function H.getNum(ent, method)  return H.get(ent, method, isnumber) end
function H.getBool(ent, method) return H.get(ent, method, isbool) end

function H.getColor(ent, method)
    local col = H.get(ent, method, istable)
    if not col then return nil end
    return { r = col.r or 255, g = col.g or 255, b = col.b or 255, a = col.a or 255 }
end

function H.getAngle(ent, method)
    local a = H.get(ent, method, isangle)
    if not a then return nil end
    return { p = a.p, y = a.y, r = a.r }
end

--- Call a setter method by name with a value, only when value is non-nil and
--- the setter exists. Returns true if the call was attempted and succeeded.
function H.set(ent, method, value)
    if value == nil then return false end
    if not (IsValid(ent) and isfunction(ent[method])) then return false end
    return pcall(ent[method], ent, value)
end

function H.setColor(ent, method, tbl)
    if not istable(tbl) then return false end
    return H.set(ent, method, Color(tbl.r or 255, tbl.g or 255, tbl.b or 255, tbl.a or 255))
end

function H.setAngle(ent, method, tbl)
    if not istable(tbl) then return false end
    return H.set(ent, method, Angle(tbl.p or 0, tbl.y or 0, tbl.r or 0))
end

--- Capture non-default bodygroups as { [id] = value }.
function H.captureBodygroups(ent)
    if not (IsValid(ent) and isfunction(ent.GetBodygroups)) then return nil end
    local ok, groups = pcall(ent.GetBodygroups, ent)
    if not ok or not istable(groups) then return nil end
    local out
    for _, g in ipairs(groups) do
        local id = g.id
        local val = isfunction(ent.GetBodygroup) and ent:GetBodygroup(id) or 0
        if val and val ~= 0 then
            out = out or {}
            out[id] = val
        end
    end
    return out
end

function H.applyBodygroups(ent, bg)
    if not (istable(bg) and IsValid(ent) and isfunction(ent.SetBodygroup)) then return end
    for id, val in pairs(bg) do
        pcall(ent.SetBodygroup, ent, tonumber(id) or id, val)
    end
end

--- Common cosmetic capture (color/skin/bodygroups) reused by most adapters.
function H.captureCosmetic(ent, root, colorGetter)
    root.color      = H.getColor(ent, colorGetter or "GetColor")
    root.skin       = H.getNum(ent, "GetSkin")
    root.bodygroups = H.captureBodygroups(ent)
end

function H.applyCosmetic(ent, root, colorSetter)
    if istable(root.color) then
        H.setColor(ent, colorSetter or "SetColor", root.color)
        if isfunction(ent.SetRenderMode) then
            pcall(ent.SetRenderMode, ent, (root.color.a or 255) < 255 and RENDERMODE_TRANSALPHA or RENDERMODE_NORMAL)
        end
    end
    H.set(ent, "SetSkin", root.skin)
    H.applyBodygroups(ent, root.bodygroups)
end

--- Physics-valid readiness probe used by bases without an explicit ready flag.
function H.physReady(ent)
    if not IsValid(ent) then return false end
    local phys = isfunction(ent.GetPhysicsObject) and ent:GetPhysicsObject()
    return IsValid(phys)
end

--- Standard occupied-seat capture: every seat that currently holds a human,
--- with the player's identity attached. Shared by all adapters.
function H.captureOccupiedSeats(ent)
    local Seats = include("rareload/core/vehicles/rareload_vehicle_seats.lua")
    local out = {}
    for _, seat in ipairs(Seats.Enumerate(ent)) do
        local driver = isfunction(seat.GetDriver) and seat:GetDriver()
        if IsValid(driver) and driver:IsPlayer() then
            local desc = Seats.BuildDescriptor(ent, seat)
            if desc then
                desc.vehClass = ent:GetClass()
                desc.occupant = { kind = "player", steamID = driver:SteamID(), steamID64 = driver:SteamID64() }
                out[#out + 1] = desc
            end
        end
    end
    return out
end

return H
