---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

-- This function is called when the addon need to restore entities from a save file. Allow to restore entities, their position, health, etc.
function RARELOAD.RestoreEntities()
    local delay = RARELOAD.settings.restoreDelay or 1

    timer.Simple(delay, function()
        if not SavedInfo or not SavedInfo.entities or #SavedInfo.entities == 0 then
            return
        end

        local stats = {
            total = #SavedInfo.entities,
            restored = 0,
            skipped = 0,
            failed = 0,
            startTime = SysTime()
        }

        local entityData = {
            restored = {},
            skipped = {},
            failed = {}
        }
        local errorMessages = {}

        local existingEntities = {}
        for _, ent in ipairs(ents.GetAll()) do
            if ent.SpawnedByRareload or ent.SavedByRareload then
                local key = ent:GetClass() .. "|" .. ent:GetModel()
                existingEntities[key] = true
            end
        end

        for _, entData in ipairs(SavedInfo.entities) do
            if not entData.class or not entData.model then
                stats.failed = stats.failed + 1
                table.insert(entityData.failed, entData)
                table.insert(errorMessages, "Missing class or model")
                continue
            end

            local entityKey = entData.class .. "|" .. entData.model

            if existingEntities[entityKey] then
                stats.skipped = stats.skipped + 1
                table.insert(entityData.skipped, entData)
                continue
            end

            local success, result = pcall(function()
                ---@class Entity
                local ent = ents.Create(entData.class)
                if not IsValid(ent) then return false, "Failed to create entity" end

                ent:SetPos(util.StringToType(entData.pos, "Vector"))
                ent:SetAngles(util.StringToType(entData.ang, "Angle"))
                ent:SetModel(entData.model)
                ent:Spawn()

                if entData.health then ent:SetHealth(entData.health) end
                if entData.color then ent:SetColor(util.StringToType(entData.color, "Color")) end
                if entData.material then ent:SetMaterial(entData.material) end

                ent.SpawnedByRareload = true
                ent.SavedByRareload = true

                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    if entData.frozen then
                        phys:EnableMotion(false)
                    end

                    if entData.velocity then
                        phys:SetVelocity(util.StringToType(entData.velocity, "Vector"))
                    end
                end

                return true, ent
            end)

            if success and result == true then
                stats.restored = stats.restored + 1
                table.insert(entityData.restored, entData)
            else
                stats.failed = stats.failed + 1
                local errorMsg = isstring(result) and result or "Unknown error"
                table.insert(entityData.failed, entData)
                table.insert(errorMessages, errorMsg)
            end
        end

        stats.endTime = SysTime()
        RARELOAD.Debug.LogEntityRestoration(stats, entityData, errorMessages)
    end)
end
