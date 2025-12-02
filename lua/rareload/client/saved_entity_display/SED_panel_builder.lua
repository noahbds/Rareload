-- Panel data building and caching logic

function SED.BuildPanelData(saved, ent, isNPC)
    if not saved then return nil end

    SED.EntityPanelCache = SED.EntityPanelCache or {}
    SED.NPCPanelCache = SED.NPCPanelCache or {}

    local panelCache = isNPC and SED.NPCPanelCache or SED.EntityPanelCache
    local id = saved.id or (saved.class .. "#" .. tostring(saved.spawnTime or 0))
    local now = CurTime()
    local entry = panelCache[id]

    local cacheLifetime = SED.INFO_CACHE_LIFETIME
    if entry and entry.expires > now then
        if IsValid(ent) and entry.data then
            local liveData = entry.data.position
            if liveData then
                local pos = ent:GetPos()
                local ang = ent:GetAngles()
                local vel = ent:GetVelocity()

                for i, line in ipairs(liveData) do
                    if line[1] == "Live Pos" then
                        line[2] = string.format("%.0f %.0f %.0f", pos.x, pos.y, pos.z)
                    elseif line[1] == "Live Ang" then
                        line[2] = string.format("%.0f %.0f %.0f", ang.p, ang.y, ang.r)
                    elseif line[1] == "Live Vel" then
                        line[2] = string.format("%.0f %.0f %.0f", vel.x, vel.y, vel.z)
                    elseif line[1] == "Live HP" and ent.Health then
                        line[2] = tostring(ent:Health())
                    end
                end
            end
        end
        return entry
    end

    local cats = {
        basic = {},
        position = {},
        saved = {},
        state = {},
        visual = {},
        behavior = {},
        physics = {},
        ownership = {},
        keyvalues = {},
        relations = {},
        combat = {},
        meta = {}
    }

    local function add(cat, label, value, col, opts)
        if value == nil or value == "" then return end
        table.insert(cats[cat], { label, tostring(value), col or SED.THEME.text, opts })
    end

    -- Basic info
    add("basic", isNPC and "NPC ID" or "Entity ID", saved.id)
    add("basic", "Class", saved.class)
    if saved.model then
        local modelName = saved.model:match("([^/\\]+)$") or saved.model
        add("basic", "Model", modelName)
    end
    if saved.owner or saved._ownerSteamID then add("basic", "Owner", saved.owner or saved._ownerSteamID) end
    if saved.spawnTime then add("basic", "Spawned", os.date("%H:%M:%S", saved.spawnTime)) end
    if saved.stateHash then add("basic", "StateHash", saved.stateHash) end
    if saved.flags and not isNPC then add("basic", "Flags", saved.flags) end

    -- Saved data
    if saved.pos then
        local p = saved.pos
        if istable(p) and p.x then
            add("saved", "Saved Position", string.format("%.1f, %.1f, %.1f", p.x, p.y, p.z), Color(100, 200, 100))
        elseif istable(p) and #p == 3 then
            add("saved", "Saved Position", string.format("%.1f, %.1f, %.1f", p[1], p[2], p[3]), Color(100, 200, 100))
        end
    end
    if saved.ang then
        local a = saved.ang
        if istable(a) and a.p then
            add("saved", "Saved Angles", string.format("%.1f, %.1f, %.1f", a.p, a.y, a.r), Color(100, 200, 100))
        elseif type(a) == "string" then
            add("saved", "Saved Angles", a, Color(100, 200, 100))
        end
    end
    if saved.velocity then
        local v = saved.velocity
        if istable(v) and v.x then
            add("saved", "Saved Velocity", string.format("%.1f, %.1f, %.1f", v.x, v.y, v.z), Color(150, 150, 200))
        elseif type(v) == "string" then
            add("saved", "Saved Velocity", v, Color(150, 150, 200))
        end
    end
    if saved.SavedAt then
        add("saved", "Save Timestamp", os.date("%Y-%m-%d %H:%M:%S", saved.SavedAt), Color(200, 200, 150))
    end
    if saved.creationTime then
        add("saved", "Creation Time", string.format("%.2f", saved.creationTime), Color(200, 200, 150))
    end
    if saved.SavedByRareload ~= nil then
        add("saved", "Saved By Rareload", saved.SavedByRareload and "Yes" or "No", Color(200, 150, 200))
    end

    -- New duplicator indicator
    if saved.SavedViaDuplicator ~= nil then
        add("saved", "Saved via Duplicator", saved.SavedViaDuplicator and "Yes" or "No", Color(100, 150, 255))
    end

    -- Physics data
    if saved.physics and istable(saved.physics) then
        local phys = saved.physics
        if phys.exists ~= nil then add("saved", "Physics Exists", phys.exists and "Yes" or "No") end
        if phys.velocity then add("saved", "Physics Velocity", phys.velocity) end
        if phys.frozen ~= nil then add("saved", "Physics Frozen", phys.frozen and "Yes" or "No") end
        if phys.mass then add("saved", "Physics Mass", phys.mass) end
        if phys.material then add("saved", "Physics Material", phys.material) end
        if phys.gravityEnabled ~= nil then add("saved", "Gravity Enabled", phys.gravityEnabled and "Yes" or "No") end
        if phys.motionEnabled ~= nil then add("saved", "Motion Enabled", phys.motionEnabled and "Yes" or "No") end
    end

    -- NPC specific saved data
    if isNPC then
        if saved.isControlled ~= nil then add("saved", "Was Controlled", saved.isControlled and "Yes" or "No") end
        if saved.expression then add("saved", "Expression", saved.expression) end
        if saved.cycle then add("saved", "Anim Cycle", string.format("%.3f", saved.cycle)) end
        if saved.sequence then add("saved", "Sequence", saved.sequence) end
        if saved.playbackRate then add("saved", "Playback Rate", string.format("%.2f", saved.playbackRate)) end
    end

    -- Position data
    if saved.pos then
        local p = saved.pos
        if istable(p) and p.x then
            add("position", "Saved Pos", string.format("%.0f %.0f %.0f", p.x, p.y, p.z))
        end
    end
    if saved.ang then
        local a = saved.ang
        if istable(a) and a.p then
            add("position", "Saved Ang", string.format("%.0f %.0f %.0f", a.p, a.y, a.r))
        end
    end
    if saved.velocity then
        local v = saved.velocity
        if istable(v) and v.y then
            add("position", "Saved Vel", string.format("%.0f %.0f %.0f", v.y, v.x, v.z))
        end
    end

    -- Live data
    if IsValid(ent) then
        local pos = ent:GetPos()
        local ang = ent:GetAngles()
        local vel = ent:GetVelocity()
        add("position", "Live Pos", string.format("%.0f %.0f %.0f", pos.x, pos.y, pos.z))
        add("position", "Live Ang", string.format("%.0f %.0f %.0f", ang.p, ang.y, ang.r))
        add("position", "Live Vel", string.format("%.0f %.0f %.0f", vel.x, vel.y, vel.z))
    end

    -- State information
    if IsValid(ent) and ent.Health then add("state", "Live HP", ent:Health()) end
    add("state", "Saved HP", saved.health)
    add("state", "Max HP", saved.maxHealth)
    add("state", "MoveType", saved.moveType)
    if isNPC then
        add("state", "NPC State", saved.npcState)
        add("state", "Hull", saved.hullType)
        add("state", "SchedID", saved.schedule and saved.schedule.id)
        add("state", "Cycle", saved.cycle and string.format("%.2f", saved.cycle))
        add("state", "Seq", saved.sequence)
        add("state", "Playback", saved.playbackRate)
    else
        add("state", "Frozen", saved.frozen == nil and nil or (saved.frozen and "Yes" or "No"))
    end

    -- NPC specific behavior and combat data
    if isNPC then
        if saved.squad then add("behavior", "Squad", saved.squad) end
        if saved.squadLeader ~= nil then add("behavior", "Leader", saved.squadLeader and "Yes" or "No") end
        if saved.target and saved.target.type then
            add("behavior", "Target", saved.target.type .. ":" .. (saved.target.id or saved.target.class or "?"))
        end
        if saved.weapons and #saved.weapons > 0 then add("combat", "Weapons", #saved.weapons) end
        if istable(saved.weapons) then
            local limit = 16
            local shown = 0
            for i, w in ipairs(saved.weapons) do
                if istable(w) then
                    add("combat", "W" .. i, w.class or w.name)
                    shown = shown + 1
                    if shown >= limit then break end
                end
            end
            if #saved.weapons > limit then
                add("combat", "+more", ("%d more..."):format(#saved.weapons - limit))
            end
        end
        if saved.weaponProficiency then add("combat", "Proficiency", saved.weaponProficiency) end
        if saved.playerRelationship then add("relations", "PlayerRel", saved.playerRelationship) end
        if saved.relations and saved.relations.players then
            local count = table.Count(saved.relations.players)
            add("relations", "Player Rels", count)
            local shown = 0
            for steamid, rel in pairs(saved.relations.players) do
                if shown >= 2 then break end
                add("relations", tostring(steamid):sub(-6), rel)
                shown = shown + 1
            end
        end
        if saved.squadMembers and #saved.squadMembers > 0 then add("relations", "SquadMembers", #saved.squadMembers) end
        if saved.vjBaseData and saved.vjBaseData.isVJBaseNPC then
            add("behavior", "VJ Type", saved.vjBaseData.vjType ~= "" and saved.vjBaseData.vjType or "VJBase")
            add("behavior", "RunSpeed", saved.vjBaseData.runSpeed)
        end
    end

    -- Visual data
    add("visual", "Skin", saved.skin)
    if saved.bodygroups then add("visual", "Bodygroups", table.Count(saved.bodygroups)) end
    add("visual", "ModelScale", saved.modelScale)
    add("visual", "RenderMode", saved.renderMode)
    add("visual", "RenderFX", saved.renderFX)
    add("visual", "Material", saved.material or saved.materialOverride)
    if saved.color and saved.color.r then
        add("visual", "Color", string.format("%d,%d,%d", saved.color.r, saved.color.g, saved.color.b))
    end
    if saved.bloodColor then add("visual", "Blood", saved.bloodColor) end

    -- Bodygroups
    if istable(saved.bodygroups) then
        local count = 0
        local limit = 24
        for k, v in pairs(saved.bodygroups) do
            add("visual", "BG " .. k, v)
            count = count + 1
            if count >= limit then break end
        end
        if table.Count(saved.bodygroups) > count then
            add("visual", "+more", ("%d more..."):format(table.Count(saved.bodygroups) - count))
        end
    end

    -- SubMaterials
    if istable(saved.subMaterials) then
        local count = 0
        local limit = 20
        for idx, mat in pairs(saved.subMaterials) do
            add("visual", "SubMat" .. idx, mat ~= "" and (mat:match("([^/\\]+)$") or mat) or "<default>")
            count = count + 1
            if count >= limit then break end
        end
        if table.Count(saved.subMaterials) > count then
            add("visual", "+more", ("%d more..."):format(table.Count(saved.subMaterials) - count))
        end
    end

    -- Physics information
    if not isNPC then
        if istable(saved.frozenPhysics) then add("physics", "FrozenPhys", table.Count(saved.frozenPhysics)) end
        if saved.mass then add("physics", "Mass", saved.mass) end
        if saved.solidType then add("physics", "Solid", saved.solidType) end
        if saved.collisionGroup then add("physics", "CollGroup", saved.collisionGroup) end
        if saved.gravity ~= nil then add("physics", "Gravity", saved.gravity and "On" or "Off") end
        if saved.drag ~= nil then add("physics", "Drag", saved.drag and "On" or "Off") end
        if saved.buoyancy ~= nil then add("physics", "Buoyancy", saved.buoyancy) end
        if saved.physicsMaterial then add("physics", "PhysMat", saved.physicsMaterial) end
    else
        if saved.hullType then add("physics", "Hull", saved.hullType) end
        if saved.collisionGroup then add("physics", "CollGroup", saved.collisionGroup) end
        if saved.solidType then add("physics", "Solid", saved.solidType) end
    end

    -- Ownership data
    if saved.spawnflags then add("ownership", "SpawnFlags", saved.spawnflags) end
    if saved.originallySpawnedBy then add("ownership", "SpawnedBy", saved.originallySpawnedBy) end
    if saved.ownerSteamID then add("ownership", "OwnerID", saved.ownerSteamID) end

    -- KeyValues
    if istable(saved.keyvalues) or istable(saved.keyValues) then
        local kv = saved.keyvalues or saved.keyValues
        local added = 0
        local limit = 60
        for k, v in pairs(kv) do
            add("keyvalues", tostring(k), type(v) == "string" and v or tostring(v))
            added = added + 1
            if added >= limit then break end
        end
        if table.Count(kv) > added then
            add("keyvalues", "+more", ("%d more..."):format(table.Count(kv) - added))
        end
    end

    -- Meta data (remaining fields)
    local used = {}
    for cname, list in pairs(cats) do
        for _, line in ipairs(list) do
            used[line[1]] = true
        end
    end

    local metaCount = 0
    for k, v in pairs(saved) do
        if k ~= "_ownerSteamID" and k ~= "id" and not used[k] and metaCount < 10 then
            local t = type(v)
            if t == "table" then
                local count = table.Count(v)
                if count == 0 then
                    add("meta", k, "{}")
                elseif count <= 8 then
                    local parts = {}
                    local simple = true
                    for kk, vv in pairs(v) do
                        if type(vv) == "table" then
                            simple = false
                            break
                        end
                        parts[#parts + 1] = kk .. "=" .. tostring(vv)
                    end
                    if simple then
                        add("meta", k, "{" .. table.concat(parts, ",") .. "}")
                    else
                        add("meta", k, "table(" .. count .. ")")
                    end
                else
                    add("meta", k, "table(" .. count .. ")")
                end
            else
                add("meta", k, v)
            end
            metaCount = metaCount + 1
        end
    end

    -- Bound total lines per category to avoid pathological frames
    local function clampCategory(catId)
        local list = cats[catId]
        if not list then return end
        local maxLines = 200
        if #list > maxLines then
            local extra = #list - maxLines
            while #list > maxLines do table.remove(list) end
            list[#list + 1] = { "+more", ("%d more..."):format(extra), SED.THEME.text }
        end
    end
    for k, _ in pairs(cats) do clampCategory(k) end

    entry = {
        data = cats,
        expires = now + SED.INFO_CACHE_LIFETIME * 2,
        activeCat = (panelCache[id] and panelCache[id].activeCat) or "basic",
        widths = {}
    }
    panelCache[id] = entry
    return entry
end
