-- Deterministic unique ID generation similar to NPC saver
---@diagnostic disable: undefined-field, inject-field, need-check-nil

if not RARELOAD then RARELOAD = {} end
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

local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")

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
            local owner = (isfunction(ent.CPPIGetOwner) and ent:CPPIGetOwner()) or nil
            local isOwnerBot = false
            if IsValid(owner) and owner.IsBot then
                local ok, res = pcall(function() return owner:IsBot() end)
                if ok and res then isOwnerBot = true end
            end
            local ownerValid = IsValid(owner) and (isOwnerBot or owner == ply)
            local spawnedByRareload = ent.SpawnedByRareload == true
            if ownerValid or spawnedByRareload then
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

                if not ent.OriginalSpawner then
                    local sid = GetOwnerSteamID(owner)
                    if sid then
                        ---@diagnostic disable-next-line: inject-field
                        ent.OriginalSpawner = sid
                    end
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

    local payload = DuplicatorBridge.DeserializePayload(duplicatorSnapshot.payload) or {}
    local entList = payload.Entities or {}
    local built = {}
    for _, dupEnt in pairs(entList) do
        local e = {}
        e.class = dupEnt.Class or dupEnt.class or dupEnt.ClassName or dupEnt.Class
        -- Map position
        if dupEnt.Pos then
            local p = dupEnt.Pos
            e.pos = { x = p.x or 0, y = p.y or 0, z = p.z or 0 }
        end
        -- Map angle
        if dupEnt.Angle or dupEnt.Ang then
            local a = dupEnt.Angle or dupEnt.Ang
            e.ang = { p = a.p or 0, y = a.y or 0, r = a.r or 0 }
        end
        e.id = dupEnt.RareloadEntityID or dupEnt.RareloadID
        e.model = dupEnt.Model or dupEnt.model
        e.skin = dupEnt.Skin or dupEnt.skin
        if dupEnt.BodyG then
            e.bodygroups = dupEnt.BodyG
        end
        if dupEnt._DuplicatedColor then
            local c = dupEnt._DuplicatedColor
            e.color = { r = c.r or 255, g = c.g or 255, b = c.b or 255, a = c.a or 255 }
        end
        if dupEnt.CurHealth ~= nil then e.health = dupEnt.CurHealth end
        if dupEnt.MaxHealth ~= nil then e.maxHealth = dupEnt.MaxHealth end
        if dupEnt.Name then e.name = dupEnt.Name end
        if dupEnt._DuplicatedMaterial then e.material = dupEnt._DuplicatedMaterial end
        if dupEnt.OriginalSpawner then e.originallySpawnedBy = dupEnt.OriginalSpawner end
        if dupEnt.SavedAt then
            e.spawnTime = dupEnt.SavedAt
        else
            e.spawnTime = duplicatorSnapshot.savedAt
        end
        e.SavedViaDuplicator = true

        if RARELOAD.Util and RARELOAD.Util.GenerateEntityStateHash then
            e.stateHash = RARELOAD.Util.GenerateEntityStateHash(e)
        end

        table.insert(built, e)
    end
    
    -- Preserve the duplicator snapshot while building the entity list
    entities = built
    entities.__duplicator = duplicatorSnapshot

    if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Saved " ..
            count .. " entities in " .. math.Round((SysTime() - startTime) * 1000) .. " ms")

        if duplicatorSnapshot then
            print(string.format("[RARELOAD DEBUG] Duplicator snapshot captured (%d entities, %d constraints)",
                duplicatorSnapshot.entityCount or 0,
                duplicatorSnapshot.constraintCount or 0))
        end
    end

    return entities
end
