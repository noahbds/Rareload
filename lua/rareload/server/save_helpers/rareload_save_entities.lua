return function(ply)
    local entities = {}
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
            local owner = ent:CPPIGetOwner()
            if (IsValid(owner) and owner:IsPlayer()) or ent.SpawnedByRareload then
                local entityData = {
                    class = ent:GetClass(),
                    pos = ent:GetPos(),
                    ang = ent:GetAngles(),
                    model = ent:GetModel(),
                    health = ent:Health(),
                    maxHealth = ent:GetMaxHealth(),
                    frozen = IsValid(ent:GetPhysicsObject()) and not ent:GetPhysicsObject():IsMotionEnabled(),
                }
                table.insert(entities, entityData)
            end
        end
    end
    return entities
end
