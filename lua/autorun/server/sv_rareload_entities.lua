function SaveEntityData(entity, playerData)
    if not IsValid(entity) then return end

    local entityData = {
        class = entity:GetClass(),
        model = entity:GetModel(),
        pos = entity:GetPos(),
        ang = entity:GetAngles(),
        health = entity:Health(),
        frozen = IsValid(entity:GetPhysicsObject()) and not entity:GetPhysicsObject():IsMotionEnabled(),
        skin = entity:GetSkin(),
        bodygroups = {},
        keyValues = {},
    }

    -- Save bodygroups
    for i = 0, entity:GetNumBodyGroups() - 1 do
        entityData.bodygroups[i] = entity:GetBodygroup(i)
    end

    -- Save keyvalues for specific types of entities
    local keyValues = {
        "spawnflags", "squadname", "targetname",
        "health", "rendercolor", "rendermode", "renderamt"
    }

    for _, keyName in ipairs(keyValues) do
        local value = entity:GetKeyValues()[keyName]
        if value then
            entityData.keyValues[keyName] = value
        end
    end

    table.insert(playerData.entities, entityData)
end
