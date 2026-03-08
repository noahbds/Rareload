-- Deterministic unique ID generation similar to NPC saver
---@diagnostic disable: undefined-field, inject-field, need-check-nil

if not RARELOAD then RARELOAD = {} end

-- Include ownership system
if not RARELOAD.Ownership then
    include("rareload/utils/rareload_ownership.lua")
end

if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local function GenerateEntityUniqueID(ent)
    return RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID and RARELOAD.Util.GenerateDeterministicID(ent) or
        "ent_legacyid"
end

local function GetOwnerSteamID(owner)
    if not IsValid(owner) then return nil end
    if owner.SteamID then
        local ok, sid = pcall(owner.SteamID, owner)
        if ok and isstring(sid) then return sid end
    end
    if owner.SteamID64 then
        local ok, sid = pcall(owner.SteamID64, owner)
        if ok and isstring(sid) then return sid end
    end
    return nil
end

local function IsEntityOwnedByPlayer(ent, ply)
    if not IsValid(ent) or not IsValid(ply) then return false end

    if RARELOAD.Ownership and RARELOAD.Ownership.IsOwner then
        local ok, isOwner = pcall(RARELOAD.Ownership.IsOwner, ent, ply)
        if ok and isOwner then
            return true
        end
    end

    if RARELOAD.Ownership and RARELOAD.Ownership.GetOwnerSteamID then
        local ok, sid = pcall(RARELOAD.Ownership.GetOwnerSteamID, ent)
        if ok and isstring(sid) and sid ~= "" and sid == ply:SteamID() then
            return true
        end
    end

    local owner = RARELOAD.Ownership and RARELOAD.Ownership.GetOwner and RARELOAD.Ownership.GetOwner(ent) or nil
    return IsValid(owner) and owner == ply
end

local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

-- Duplicator-driven only: old per-entity save logic removed.

local function CaptureDuplicatorSnapshot(ply, trackedEntities)
    if not (DuplicatorBridge and DuplicatorBridge.IsSupported and DuplicatorBridge.IsSupported()) then
        return nil
    end

    if not istable(trackedEntities) or #trackedEntities == 0 then
        return nil
    end

    local snapshot, err = DuplicatorBridge.CaptureSnapshot(trackedEntities, {
        ownerSteamID = (IsValid(ply) and ply.SteamID and ply:SteamID()) or nil,
        ownerSteamID64 = (IsValid(ply) and ply.SteamID64 and ply:SteamID64()) or nil,
        anchor = IsValid(ply) and ply:GetPos() or nil
    })

    if not snapshot and err and RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD] Duplicator snapshot capture failed: " .. tostring(err))
    end

    return snapshot
end

return function(ply)
    if not IsValid(ply) then return {} end

    local entities = {}
    local count = 0
    local startTime = SysTime()
    local duplicatorTargets = {}
    local duplicatorSeen = {}

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
            local owner = RARELOAD.Ownership and RARELOAD.Ownership.GetOwner(ent) or nil
            local ownerValid = IsEntityOwnedByPlayer(ent, ply)
            if ownerValid then
                count = count + 1

                if not ent.RareloadEntityID then
                    ---@diagnostic disable-next-line: inject-field
                    ent.RareloadEntityID = GenerateEntityUniqueID(ent)
                    if ent.SetNWString then
                        pcall(function() ent:SetNWString("RareloadID", ent.RareloadEntityID) end)
                    end
                end

                if ent.SetNWString and ent.RareloadEntityID and (ent.GetNWString and ent:GetNWString("RareloadID", "") == "") then
                    pcall(function() ent:SetNWString("RareloadID", ent.RareloadEntityID) end)
                end


                if not duplicatorSeen[ent] then
                    duplicatorSeen[ent] = true
                    duplicatorTargets[#duplicatorTargets + 1] = ent
                end

                local sid = GetOwnerSteamID(owner) or (RARELOAD.Ownership and RARELOAD.Ownership.GetOwnerSteamID and
                    RARELOAD.Ownership.GetOwnerSteamID(ent)) or nil
                if sid then
                    ---@diagnostic disable-next-line: inject-field
                    ent.OriginalSpawner = sid
                end

            end
        end
    end

    local duplicatorSnapshot = CaptureDuplicatorSnapshot(ply, duplicatorTargets)
    if not duplicatorSnapshot then
        if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print(string.format("[RARELOAD DEBUG] Duplicator snapshot unavailable, saved %d entities candidates (no snapshot)", count))
        end

        return {}
    end

    SnapshotUtils.EnsureIndexMap(duplicatorSnapshot, {
        category = "entity",
        idPrefix = "entity"
    })
    
    local result = {}
    rawset(result, "__duplicator", duplicatorSnapshot)

    if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Saved " ..
            count .. " entities in " .. math.Round((SysTime() - startTime) * 1000) .. " ms")

        if duplicatorSnapshot then
            print(string.format("[RARELOAD DEBUG] Duplicator snapshot captured (%d entities, %d constraints)",
                duplicatorSnapshot.entityCount or 0,
                duplicatorSnapshot.constraintCount or 0))
        end
    end

    return result
end
