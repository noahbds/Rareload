return function(ply)
    if not IsValid(ply) then return {} end

    local entities = {}
    local count = 0
    local startTime = SysTime()

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
            local owner = ent:CPPIGetOwner()
            if (IsValid(owner) and (owner:IsBot() or owner == ply)) or ent.SpawnedByRareload then
                count = count + 1

                if not ent.RareloadEntityID then
                    ent.RareloadEntityID = "ent_" .. ent:EntIndex() .. "_" .. os.time() .. "_" .. math.random(1000, 9999)
                end

                local entityData = {
                    id = ent.RareloadEntityID,
                    class = ent:GetClass(),
                    pos = { x = ent:GetPos().x, y = ent:GetPos().y, z = ent:GetPos().z },
                    ang = { p = ent:GetAngles().p, y = ent:GetAngles().y, r = ent:GetAngles().r },
                    model = ent:GetModel(),
                    health = ent:Health(),
                    maxHealth = ent:GetMaxHealth(),
                    frozen = IsValid(ent:GetPhysicsObject()) and not ent:GetPhysicsObject():IsMotionEnabled(),
                    owner = IsValid(owner) and owner:SteamID() or nil,
                    originallySpawnedBy = ent.OriginalSpawner or (IsValid(owner) and owner:SteamID() or nil),
                    spawnTime = ent.SpawnTime or os.time(),
                    wasPlayerSpawned = not ent.SpawnedByRareload
                }

                if ent:GetColor() then
                    entityData.color = {
                        r = ent:GetColor().r,
                        g = ent:GetColor().g,
                        b = ent:GetColor().b,
                        a = ent:GetColor().a
                    }
                end

                if ent:GetMaterial() and ent:GetMaterial() ~= "" then
                    entityData.material = ent:GetMaterial()
                end

                if ent:GetSkin() then
                    entityData.skin = ent:GetSkin()
                end

                ent.SavedByRareload = true
                if not ent.OriginalSpawner and IsValid(owner) then
                    ent.OriginalSpawner = owner:SteamID()
                end

                table.insert(entities, entityData)
            end
        end
    end

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Saved " ..
            count .. " entities in " .. math.Round((SysTime() - startTime) * 1000) .. " ms")
    end

    return entities
end
