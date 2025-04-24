local function SpawnEntityByBot(bot)
    if not IsValid(bot) or not bot:IsBot() then return end

    local ent = ents.Create("prop_physics")
    if not IsValid(ent) then return end

    ent:SetModel("models/props_c17/oildrum001.mdl")
    ent:SetPos(bot:GetPos() + bot:GetForward() * 50 + Vector(0, 0, 50))
    ent:Spawn()
    ent:Activate()
    ent:SetOwner(bot)
    ent.SpawnedByRareload = true

    print(bot:Nick() .. " has spawned an entity!")
end

return function(ply)
    for _, bot in ipairs(player.GetBots()) do
        SpawnEntityByBot(bot)
    end
end
