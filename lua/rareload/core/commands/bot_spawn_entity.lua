local function SpawnEntityByBot(bot)
    if not IsValid(bot) or not bot:IsBot() then return end

    local ent = ents.Create("prop_physics")
    if not IsValid(ent) then return end

    ent:SetModel("models/props_c17/oildrum001.mdl")

    local pos = bot:GetPos()
    if type(pos) == "table" and pos.x and pos.y and pos.z then
        pos = Vector(pos.x, pos.y, pos.z)
    end
    ent:SetPos(pos + bot:GetForward() * 50 + Vector(0, 0, 50))

    ent:Spawn()
    ent:Activate()
    ent:SetOwner(bot)
    ent.SpawnedByRareload = true

    -- Add unique tracking
    ent.RareloadEntityID = "ent_" .. ent:EntIndex() .. "_" .. os.time() .. "_" .. math.random(1000, 9999)
    ent.OriginalSpawner = bot:SteamID()
    ent.SpawnTime = os.time()

    print(bot:Nick() .. " has spawned an entity with ID: " .. ent.RareloadEntityID)
end

return function(ply)
    for _, bot in ipairs(player.GetBots()) do
        SpawnEntityByBot(bot)
    end
end
