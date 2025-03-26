RARELOAD = RARELOAD or {}

function RARELOAD.AddEntitiesData(RARELOAD)
    RARELOAD.entities = {}
    local startTime = SysTime()
    local count = 0
    local skipped = 0

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
            local owner = ent:CPPIGetOwner()
            if (IsValid(owner) and owner:IsPlayer()) or ent.SpawnedByRareload then
                local success, entityData = pcall(function()
                    local data = {
                        class = ent:GetClass(),
                        pos = tostring(ent:GetPos()),
                        ang = tostring(ent:GetAngles()),
                        model = ent:GetModel(),
                        health = ent:Health(),
                        maxHealth = ent:GetMaxHealth(),
                        frozen = IsValid(ent:GetPhysicsObject()) and not ent:GetPhysicsObject():IsMotionEnabled(),
                        SavedByRareload = true
                    }

                    local color = ent:GetColor()
                    if color.r ~= 255 or color.g ~= 255 or color.b ~= 255 or color.a ~= 255 then
                        data.color = tostring(color)
                    end

                    local material = ent:GetMaterial()
                    if material and material ~= "" then
                        data.material = material
                    end

                    local phys = ent:GetPhysicsObject()
                    if IsValid(phys) then
                        data.velocity = tostring(phys:GetVelocity())
                    end

                    data.uniqueID = ent:GetClass() .. "|" .. ent:GetModel() .. "|" .. tostring(ent:GetPos())

                    return data
                end)

                if success then
                    count = count + 1
                    ent.SavedByRareload = true
                    table.insert(RARELOAD.entities, entityData)
                else
                    skipped = skipped + 1
                    if RARELOAD.settings.debugEnabled then
                        print("[RARELOAD DEBUG] Failed to save entity data: " .. tostring(entityData))
                    end
                end
            end
        end
    end

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Saved " .. count .. " entities in " ..
            math.Round((SysTime() - startTime) * 1000) .. " ms (Skipped: " .. skipped .. ")")
    end
end
