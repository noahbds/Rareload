-- ============================================================================
-- Vehicle capture (save side). Discovers the root vehicles a player owns (or is
-- actively driving), assigns each a stable RareloadEntityID.
-- ============================================================================

-- TODO : change the behavior to prevent unowned vehicule
-- from being captured but still allow the player to
-- reseat in it but only if the original vehicule or
-- the restored version from the original owner is still present
-- in the map. This will prevent players from capturing unowned vehicles
-- and then leaving them behind for other players to use.

RARELOAD = RARELOAD or {}

local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")
local SnapshotUtils  = include("rareload/shared/rareload_snapshot_utils.lua")
local Adapters       = include("rareload/core/vehicles/rareload_vehicle_adapters.lua")
local Schema         = include("rareload/core/vehicles/rareload_vehicle_schema.lua")

if not (RARELOAD.DataUtils and RARELOAD.DataUtils.IsRootVehicle) then
    include("rareload/utils/rareload_data_utils.lua")
end

local DataUtils = RARELOAD.DataUtils

local function IsRootVehicle(ent) return DataUtils and DataUtils.IsRootVehicle(ent) or false end
local function GetRootVehicle(ent) return (DataUtils and DataUtils.GetRootVehicle(ent)) or ent end

local function PlayerOccupiesVehicle(ply, root)
    if not (IsValid(ply) and IsValid(root)) then return false end
    local veh = ply:GetVehicle()
    if not IsValid(veh) then return false end
    return veh == root or GetRootVehicle(veh) == root
end

--- Capture all of a player's vehicles into a v2 bucket
--- ({ __duplicator, runtimeState, seats }).
return function(ply)
    if not IsValid(ply) then return {} end
    Adapters.EnsureLoaded()

    local Ownership = RARELOAD.Ownership
    local ResolveOwner        = Ownership and Ownership.ResolveOwner
    local IsOwnedByPlayerSafe = Ownership and Ownership.IsOwnedByPlayerSafe
    local GetPlayerSteamIDSafe = Ownership and Ownership.GetPlayerSteamIDSafe
    local GetOwnerSteamIDSafe  = Ownership and Ownership.GetOwnerSteamIDSafe
    local SetOwner             = Ownership and Ownership.SetOwner

    if Ownership and Ownership.BeginResolveBatch then Ownership.BeginResolveBatch() end

    local targets, seen = {}, {}
    local idOverrides   = {}
    local runtimeState  = {}
    local seatsByVeh    = {}
    local vehToId       = {}
    local count = 0

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then goto cont end
        if not (IsRootVehicle(ent) or ent:IsVehicle()) then goto cont end

        local veh = GetRootVehicle(ent) or ent
        if not IsValid(veh) or veh:IsPlayer() or veh:IsNPC() or veh:IsWeapon() then goto cont end
        if DataUtils and DataUtils.IsVehiclePart(veh) then goto cont end
        if seen[veh] then goto cont end

        local owner = ResolveOwner and ResolveOwner(veh) or nil
        local ownerValid = IsOwnedByPlayerSafe and IsOwnedByPlayerSafe(veh, ply)
        if not ownerValid and not IsValid(owner) then
            local claimable = PlayerOccupiesVehicle(ply, veh)
                or (isfunction(veh.GetDriver) and veh:GetDriver() == ply)
            if claimable and SetOwner then
                SetOwner(veh, ply); ownerValid = true; owner = ply
            end
        end
        if not ownerValid then goto cont end

        seen[veh] = true
        targets[#targets + 1] = veh
        count = count + 1

        local id = EntityIdentity.EnsureID(veh, "RareloadEntityID", "ent_legacyid")
        local sid = (GetPlayerSteamIDSafe and GetPlayerSteamIDSafe(owner))
            or (GetOwnerSteamIDSafe and GetOwnerSteamIDSafe(veh))
        if sid then veh.OriginalSpawner = sid end
        if id then idOverrides[veh:EntIndex()] = id; vehToId[veh] = id end

        -- Adapter-driven runtime + seat capture.
        if id then
            local adapter = Adapters.Resolve(veh)
            local entry = { adapter = adapter and adapter.id or nil }
            if adapter and isfunction(adapter.captureRoot) then
                local ok, root = pcall(adapter.captureRoot, veh)
                if ok and istable(root) and next(root) then entry.root = root end
            end
            if adapter and isfunction(adapter.captureComponents) then
                local ok, comps = pcall(adapter.captureComponents, veh)
                if ok and istable(comps) and #comps > 0 then entry.components = comps end
            end
            if entry.root or entry.components then runtimeState[tostring(id)] = entry end

            if adapter and isfunction(adapter.captureSeats) then
                local ok, seats = pcall(adapter.captureSeats, veh)
                if ok and istable(seats) and #seats > 0 then seatsByVeh[tostring(id)] = seats end
            end
        end

        ::cont::
    end

    if Ownership and Ownership.EndResolveBatch then Ownership.EndResolveBatch() end

    local phantomParts = {}
    if next(vehToId) then
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and DataUtils and DataUtils.IsVehiclePart(ent)
                and not ent:IsVehicle()
                and not ent:GetNoDraw() and ent:GetColor().a > 0 then
                local mdl = ent:GetModel()
                if isstring(mdl) and mdl ~= "" and mdl ~= "models/error.mdl" then
                    local root = GetRootVehicle(ent)
                    local id = root and vehToId[root]
                    if id then
                        local lp = root:WorldToLocal(ent:GetPos())
                        local la = root:WorldToLocalAngles(ent:GetAngles())
                        local list = phantomParts[id]
                        if not list then list = {}; phantomParts[id] = list end
                        list[#list + 1] = {
                            model = mdl,
                            skin  = ent:GetSkin() or 0,
                            lp    = { x = lp.x, y = lp.y, z = lp.z },
                            la    = { p = la.p, y = la.y, r = la.r },
                        }
                    end
                end
            end
        end
    end

    local bucket = SnapshotUtils.BuildOwnedBucket(ply, targets, {
        captureOpts = { category = "vehicle" },
        indexMap    = { category = "vehicle", idPrefix = "vehicle" },
        extras      = { rareloadIDOverrides = idOverrides, phantomParts = phantomParts },
        keepTargets = true,
    })
    if not SnapshotUtils.HasSnapshot(bucket) then return bucket end

    Schema.Finalize(bucket, runtimeState, seatsByVeh)
    return bucket
end
