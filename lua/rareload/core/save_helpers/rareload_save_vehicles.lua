if not RARELOAD then RARELOAD = {} end

-- Include ownership system
if not RARELOAD.Ownership then
    include("rareload/utils/rareload_ownership.lua")
end

local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")
local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")
local DebugHelpers = include("rareload/debug/sv_debug_helpers.lua")

if not (RARELOAD.DataUtils and RARELOAD.DataUtils.IsVehicleEntity) then
    include("rareload/utils/rareload_data_utils.lua")
end

---@param ply? Player|Entity
---@param level? string
---@param message? string
---@param details? any
---@param opts? table
---@return boolean|nil
local function WriteVehicleSaveDebug(ply, level, message, details, opts)
    if DebugHelpers and DebugHelpers.Write then
        local merged = {
            gate = true,
            allowPrintFallback = true,
            printPrefix = "[RARELOAD DEBUG] ",
            ply = ply
        }
        if istable(opts) then
            for k, v in pairs(opts) do merged[k] = v end
        end
        return DebugHelpers.Write("vehicle_save", level, message, details, merged)
    end
end


-- ============================================================================
-- LOOKUP ARRAYS
-- ============================================================================

local OCCUPANCY_KEYS = {
    "LFSBaseEnt", "lvsBaseEnt", "VehicleBase", "wac_base", "baseEnt", "BaseEnt", "pPodOwner"
}

local OWNER_KEYS = {
    "dOwnerEntLFS", "LFSOwner", "SpawnerPlayer", "RareloadOwner"
}


-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

local DataUtils = RARELOAD.DataUtils

local function IsVehicleEntity(ent)
    return DataUtils and DataUtils.IsVehicleEntity(ent) or (IsValid(ent) and ent:IsVehicle())
end

local function GetRootVehicle(ent)
    return (DataUtils and DataUtils.GetRootVehicle(ent)) or ent
end

local function PlayerOccupiesVehicle(ply, root)
    if not (IsValid(ply) and IsValid(root)) then return false end
    local veh = ply:GetVehicle()
    if not IsValid(veh) then return false end

    if veh == root or GetRootVehicle(veh) == root or root == GetRootVehicle(veh) then return true end
    if veh:GetParent() == root then return true end

    for _, key in ipairs(OCCUPANCY_KEYS) do
        if veh[key] == root then return true end
    end

    return false
end


-- ============================================================================
-- PHANTOM VISUAL PARTS
-- ============================================================================
local MAX_VISUAL_PARTS = 32
local MAX_POSE_BONES = 128

local function GatherVehicleVisualParts(root)
    if not IsValid(root) then return nil end

    local baseModel = string.lower(root:GetModel() or "")
    local rootPos, rootAng = root:GetPos(), root:GetAngles()
    local parts, seen, count = {}, {}, 0

    local function consider(ent)
        if count >= MAX_VISUAL_PARTS or not IsValid(ent) or ent == root then return end
        if ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then return end

        local mdl = ent:GetModel()
        if not isstring(mdl) or mdl == "" then return end

        local lower = string.lower(mdl)
        if lower == baseModel or seen[lower] or not string.EndsWith(lower, ".mdl") then return end

        if ent:GetNoDraw() or (ent.GetRenderMode and ent:GetRenderMode() == RENDERMODE_NONE) or IsVehicleEntity(ent) then return end

        seen[lower] = true
        count = count + 1

        local lpos, lang = WorldToLocal(ent:GetPos(), ent:GetAngles(), rootPos, rootAng)
        parts[#parts + 1] = {
            model = mdl,
            skin  = ent:GetSkin() or 0,
            pos   = { x = lpos.x, y = lpos.y, z = lpos.z },
            ang   = { p = lang.p, y = lang.y, r = lang.r },
        }
    end

    if constraint and constraint.GetAllConstrainedEntities then
        local ok, constrained = pcall(constraint.GetAllConstrainedEntities, root)
        if ok and istable(constrained) then
            for _, ent in pairs(constrained) do consider(ent) end
        end
    end

    local function walkChildren(ent, depth)
        if depth > 6 or not IsValid(ent) then return end
        for _, child in ipairs(ent:GetChildren() or {}) do
            consider(child)
            walkChildren(child, depth + 1)
        end
    end
    walkChildren(root, 0)

    return #parts > 0 and parts or nil
end

local function GatherVehicleAppearance(root)
    if not IsValid(root) then return nil end
    local appearance = { skin = root:GetSkin() or 0 }
    local bodygroups

    for _, bg in ipairs(root:GetBodyGroups() or {}) do
        local value = root:GetBodygroup(bg.id)
        if value and value ~= 0 then
            bodygroups = bodygroups or {}
            bodygroups[bg.id] = value
        end
    end
    appearance.bodygroups = bodygroups

    return appearance
end

local function GatherVehiclePose(root)
    if not IsValid(root) then return nil end
    local pose = {}

    local seq = root:GetSequence()
    if seq and seq >= 0 then
        pose.sequence = seq
        pose.cycle    = root:GetCycle() or 0
    end

    local numPP = root:GetNumPoseParameters() or 0
    if numPP > 0 then
        local params = {}
        for i = 0, numPP - 1 do
            local name = root:GetPoseParameterName(i)
            if isstring(name) and name ~= "" then
                local minv, maxv = root:GetPoseParameterRange(i)
                local norm = root:GetPoseParameter(i)
                if minv and maxv then
                    params[name] = minv + (norm or 0) * (maxv - minv)
                end
            end
        end
        if next(params) then pose.poseParams = params end
    end

    local numBones = root:GetBoneCount() or 0
    if numBones > 0 and numBones <= MAX_POSE_BONES then
        local bones
        for b = 0, numBones - 1 do
            local ang = root:GetManipulateBoneAngles(b)
            local pos = root:GetManipulateBonePosition(b)
            local scl = root:GetManipulateBoneScale(b)

            local hasAng = ang and (ang.p ~= 0 or ang.y ~= 0 or ang.r ~= 0)
            local hasPos = pos and (pos.x ~= 0 or pos.y ~= 0 or pos.z ~= 0)
            local hasScl = scl and (scl.x ~= 1 or scl.y ~= 1 or scl.z ~= 1)

            if hasAng or hasPos or hasScl then
                bones = bones or {}
                bones[b] = {
                    ang = hasAng and { p = ang.p, y = ang.y, r = ang.r } or nil,
                    pos = hasPos and { x = pos.x, y = pos.y, z = pos.z } or nil,
                    scl = hasScl and { x = scl.x, y = scl.y, z = scl.z } or nil,
                }
            end
        end
        if bones then pose.bones = bones end
    end

    return next(pose) and pose or nil
end

local function BuildSeatDescriptor(root, seat)
    if not IsValid(seat) then return nil end
    local info = { class = seat:GetClass() }

    if isfunction(seat.lvsGetPodIndex) then
        local ok, idx = pcall(seat.lvsGetPodIndex, seat)
        if ok and isnumber(idx) and idx >= 0 then info.podIndex = idx end
    end
    if not info.podIndex and isfunction(seat.GetNWInt) then
        local idx = seat:GetNWInt("pPodIndex", -1)
        if idx and idx >= 0 then info.podIndex = idx end
    end

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

-- ============================================================================
-- MAIN SAVE FUNCTION
-- ============================================================================

return function(ply)
    if not IsValid(ply) then return {} end

    local count = 0
    local startTime = SysTime()

    local duplicatorTargets = {}
    local duplicatorSeen = {}

    local idOverrides = {}
    local visuals = {}

    -- Localize API calls for the O(N) loop to minimize global table lookups
    local ents_GetAll = ents.GetAll
    local ClassIsRootVehicle = RARELOAD.DataUtils and RARELOAD.DataUtils.ClassIsRootVehicle
    local IsVehicleSubEntity = RARELOAD.DataUtils and RARELOAD.DataUtils.IsVehicleSubEntity

    local Ownership = RARELOAD.Ownership
    local ResolveOwner = Ownership and Ownership.ResolveOwner
    local IsOwnedByPlayerSafe = Ownership and Ownership.IsOwnedByPlayerSafe
    local GetPlayerSteamIDSafe = Ownership and Ownership.GetPlayerSteamIDSafe
    local GetOwnerSteamIDSafe = Ownership and Ownership.GetOwnerSteamIDSafe
    local SetOwner = Ownership and Ownership.SetOwner

    for _, ent in ipairs(ents_GetAll()) do
        if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then continue end

        local isVeh = (ClassIsRootVehicle and ClassIsRootVehicle(ent:GetClass())) or IsVehicleEntity(ent)
        if not isVeh then continue end

        local targetEnt = GetRootVehicle(ent) or ent
        if not IsValid(targetEnt) or targetEnt:IsPlayer() or targetEnt:IsNPC() or targetEnt:IsWeapon() then continue end
        if IsVehicleSubEntity and IsVehicleSubEntity(targetEnt) then continue end

        local owner = ResolveOwner and ResolveOwner(targetEnt) or nil
        local ownerValid = IsOwnedByPlayerSafe and IsOwnedByPlayerSafe(targetEnt, ply)

        if not ownerValid and (owner == nil or not IsValid(owner)) then
            local claimable = PlayerOccupiesVehicle(ply, targetEnt)
                or (targetEnt.GetDriver and isfunction(targetEnt.GetDriver) and targetEnt:GetDriver() == ply)
                or (targetEnt.LastDriver == ply)
                or (#player.GetHumans() <= 1)

            if not claimable then
                for _, key in ipairs(OWNER_KEYS) do
                    if targetEnt[key] == ply then
                        claimable = true
                        break
                    end
                end
            end

            if claimable and SetOwner then
                SetOwner(targetEnt, ply)
                ownerValid = true
                owner = ply
            end
        end

        if not ownerValid then
            if IsVehicleEntity(ent) then
                WriteVehicleSaveDebug(ply, "VERBOSE", "Skipped vehicle (not owned by saver)",
                    string.format("class=%s owner=%s", targetEnt:GetClass(), IsValid(owner) and owner:Nick() or "none"))
            end
            continue
        end

        if not duplicatorSeen[targetEnt] then
            duplicatorSeen[targetEnt] = true
            duplicatorTargets[#duplicatorTargets + 1] = targetEnt
            count = count + 1

            local id = EntityIdentity.EnsureID(targetEnt, "RareloadEntityID", "ent_legacyid")

            local sid = (GetPlayerSteamIDSafe and GetPlayerSteamIDSafe(owner))
                or (GetOwnerSteamIDSafe and GetOwnerSteamIDSafe(targetEnt))

            if sid then targetEnt.OriginalSpawner = sid end

            -- Consolidate visuals and ID overrides directly into the first loop
            -- to avoid iterating over `duplicatorTargets` multiple times.
            if id then
                idOverrides[targetEnt:EntIndex()] = id

                local parts = GatherVehicleVisualParts(targetEnt)
                local appearance = GatherVehicleAppearance(targetEnt)
                local pose = GatherVehiclePose(targetEnt)

                if parts or appearance or pose then
                    visuals[id] = { parts = parts, appearance = appearance, pose = pose }
                end
            end
        end
    end

    local duplicatorSnapshot = DuplicatorBridge.CaptureSnapshotForPlayer(
        duplicatorTargets,
        ply,
        function(err)
            WriteVehicleSaveDebug(ply, "WARNING", "Duplicator vehicle snapshot capture failed", tostring(err))
        end,
        { category = "vehicle" }
    )

    if not duplicatorSnapshot then
        local level = (count > 0) and "WARNING" or "VERBOSE"
        local reason = (count > 0) and "Duplicator vehicle snapshot unavailable" or "No vehicle candidates to snapshot"
        WriteVehicleSaveDebug(ply, level, reason, string.format("Found %d owned vehicles (no snapshot)", count))
        return {}
    end

    if next(idOverrides) then duplicatorSnapshot.rareloadIDOverrides = idOverrides end
    if next(visuals) then duplicatorSnapshot.rareloadVisuals = visuals end

    SnapshotUtils.EnsureIndexMap(duplicatorSnapshot, { category = "vehicle", idPrefix = "vehicle" })

    local result = {}
    rawset(result, "__duplicator", duplicatorSnapshot)

    local currentVehicle = ply:GetVehicle()
    if IsValid(currentVehicle) then
        local rootVehicle = GetRootVehicle(currentVehicle) or currentVehicle
        local vehicleID = EntityIdentity.GetID(rootVehicle, "RareloadEntityID") or
        EntityIdentity.GetID(currentVehicle, "RareloadEntityID")

        if not vehicleID then
            vehicleID = EntityIdentity.EnsureID(rootVehicle, "RareloadEntityID", "ent_legacyid")
        end

        if vehicleID then
            result.vehicleState = {
                entityID       = vehicleID,
                class          = rootVehicle:GetClass(),
                savedInVehicle = true,
                seat           = BuildSeatDescriptor(rootVehicle, currentVehicle),
            }
        end
    end

    WriteVehicleSaveDebug(ply, "INFO", "Vehicle save completed", {
        string.format("Saved %d vehicles in %d ms", count, math.Round((SysTime() - startTime) * 1000)),
        string.format("Duplicator snapshot captured (%d entities, %d constraints)", duplicatorSnapshot.entityCount or 0,
            duplicatorSnapshot.constraintCount or 0)
    })

    return result
end
