---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

-- This function is called when the addon need to restore entities from a save file. Allow to restore entities, their position, health, etc.
function RARELOAD.RestoreEntities()
    timer.Simple(1, function()
        for _, entData in ipairs(SavedInfo.entities) do
            local exists = false
            for _, ent in ipairs(ents.FindInSphere(util.StringToType(entData.pos, "Vector"), 10)) do
                if ent:GetClass() == entData.class and ent:GetModel() == entData.model then
                    exists = true
                    break
                end
            end

            if not exists then
                local success, newEnt = pcall(function()
                    local ent = ents.Create(entData.class)
                    if not IsValid(ent) then return nil end

                    ent:SetPos(util.StringToType(entData.pos, "Vector"))
                    ent:SetAngles(util.StringToType(entData.ang, "Angle"))
                    ent:SetModel(entData.model)
                    ent:Spawn()
                    ent:SetHealth(entData.health)
                    ---@diagnostic disable-next-line: inject-field
                    ent.SpawnedByRareload = true

                    local phys = ent:GetPhysicsObject()
                    if IsValid(phys) and entData.frozen then
                        phys:EnableMotion(false)
                    end

                    return ent
                end)

                if not success or not IsValid(newEnt) then
                    if DebugEnabled then
                        print("[RARELOAD DEBUG] Failed to create entity: " ..
                            entData.class .. " - " .. tostring(newEnt))
                    end
                end
            end
        end
    end)
end
