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

local function MarkSaved(ent)
    ---@diagnostic disable-next-line: inject-field
    ent.SavedByRareload = true
end

return function(ply)
    if not IsValid(ply) then return {} end

    local entities = {}
    local count = 0
    local startTime = SysTime()

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

                MarkSaved(ent)

                if not ent.OriginalSpawner then
                    local sid = GetOwnerSteamID(owner)
                    if sid then
                        ---@diagnostic disable-next-line: inject-field
                        ent.OriginalSpawner = sid
                    end
                end

                local ang = ent:GetAngles() or Angle(0, 0, 0)
                local pos = ent:GetPos() or Vector(0, 0, 0)
                local col = ent.GetColor and ent:GetColor() or nil

                local entityData = {
                    id = ent.RareloadEntityID,
                    class = ent:GetClass(),
                    pos = { x = pos.x, y = pos.y, z = pos.z },
                    ang = { p = ang.p, y = ang.y, r = ang.r },
                    model = ent.GetModel and ent:GetModel() or nil,
                    health = ent.Health and ent:Health() or nil,
                    maxHealth = ent.GetMaxHealth and ent:GetMaxHealth() or nil,
                    frozen = (ent.GetPhysicsObject and IsValid(ent:GetPhysicsObject()) and not ent:GetPhysicsObject():IsMotionEnabled()) or
                        false,
                    owner = GetOwnerSteamID(owner),
                    originallySpawnedBy = ent.OriginalSpawner or GetOwnerSteamID(owner),
                    spawnTime = ent.SpawnTime or os.time(),
                    SavedByRareload = true
                }

                -- Bodygroups
                local numBG_safe = 0
                if ent.GetNumBodyGroups then
                    local okBG, nBG = pcall(ent.GetNumBodyGroups, ent)
                    if okBG and isnumber(nBG) then numBG_safe = nBG end
                end
                if numBG_safe > 0 and ent.GetBodygroup then
                    local bgt = {}
                    for i = 0, numBG_safe - 1 do
                        local okBGV, v = pcall(ent.GetBodygroup, ent, i)
                        if okBGV then bgt[i] = v end
                    end
                    if next(bgt) ~= nil then
                        entityData.bodygroups = bgt
                    end
                end

                -- Physics related
                local phys = ent.GetPhysicsObject and ent:GetPhysicsObject() or nil
                if IsValid(phys) then
                    local okMass, mass = pcall(phys.GetMass, phys)
                    if okMass and mass then entityData.mass = mass end
                    local okGrav, gravEnabled = pcall(phys.IsGravityEnabled, phys)
                    if okGrav then entityData.gravityEnabled = gravEnabled end
                    local okMat, physMat = pcall(phys.GetMaterial, phys)
                    if okMat and physMat and physMat ~= "" then entityData.physicsMaterial = physMat end
                    local okEl, el = pcall(phys.GetElasticity, phys)
                    if okEl and el then entityData.elasticity = el end
                end

                -- Velocity
                if ent.GetVelocity then
                    local okVel, vel = pcall(ent.GetVelocity, ent)
                    if okVel and vel then
                        entityData.velocity = { x = vel.x, y = vel.y, z = vel.z }
                    end
                end

                -- Render / visual state
                if ent.GetRenderMode then
                    local okRM, rm = pcall(ent.GetRenderMode, ent)
                    if okRM and rm then entityData.renderMode = rm end
                end
                if ent.GetRenderFX then
                    local okFX, fx = pcall(ent.GetRenderFX, ent)
                    if okFX and fx then entityData.renderFX = fx end
                end
                if ent.GetModelScale then
                    local okScale, scale = pcall(ent.GetModelScale, ent)
                    if okScale and scale and scale ~= 1 then entityData.modelScale = scale end
                end

                -- Collision / movement
                if ent.GetCollisionGroup then
                    local okCG, cg = pcall(ent.GetCollisionGroup, ent)
                    if okCG and cg then entityData.collisionGroup = cg end
                end
                if ent.GetMoveType then
                    local okMT, mt = pcall(ent.GetMoveType, ent)
                    if okMT and mt then entityData.moveType = mt end
                end
                if ent.GetSolid then
                    local okSolid, solid = pcall(ent.GetSolid, ent)
                    if okSolid and solid then entityData.solidType = solid end
                end

                -- Spawn flags
                if ent.GetSpawnFlags then
                    local okSF, sf = pcall(ent.GetSpawnFlags, ent)
                    if okSF and sf and sf ~= 0 then entityData.spawnFlags = sf end
                end

                -- KeyValues snapshot
                if ent.GetKeyValues then
                    local okKV, kvTbl = pcall(ent.GetKeyValues, ent)
                    if okKV and istable(kvTbl) then
                        local filtered = {}
                        -- Exclude keys we already serialize explicitly to avoid duplication
                        local EXCLUDE = {
                            health = true,
                            max_health = true,
                            spawnflags = true,
                            rendercolor = true,
                            rendermode = true,
                            skin = true,
                            modelscale = true,
                            velocity = true,
                            mass = true,
                        }
                        for k, v in pairs(kvTbl) do
                            if not EXCLUDE[k] and (type(v) == "number" or type(v) == "string") then
                                local s = tostring(v)
                                if #s <= 128 then
                                    filtered[k] = v
                                end
                            end
                        end
                        if next(filtered) then entityData.keyvalues = filtered end
                    end
                end

                -- Name / targetname
                if ent.GetName then
                    local okName, nameStr = pcall(ent.GetName, ent)
                    if okName and nameStr and nameStr ~= "" then entityData.name = nameStr end
                end

                if col then
                    entityData.color = { r = col.r, g = col.g, b = col.b, a = col.a }
                end

                if ent.GetMaterial then
                    local mat = ent:GetMaterial()
                    if mat and mat ~= "" then entityData.material = mat end
                end

                if ent.GetSkin then
                    local s = ent:GetSkin()
                    if s ~= nil then entityData.skin = s end
                end

                if RARELOAD.Util and RARELOAD.Util.GenerateEntityStateHash then
                    entityData.stateHash = RARELOAD.Util.GenerateEntityStateHash(entityData)
                end

                table.insert(entities, entityData)
            end
        end
    end

    if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Saved " ..
            count .. " entities in " .. math.Round((SysTime() - startTime) * 1000) .. " ms")
    end

    return entities
end
