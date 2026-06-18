-- Category collection logic for SED panel data builder.

if not (SED and SED.PanelBuilder) then
    include("rareload/client/saved_entity_display/SED_panel_builder_utils.lua")
end

local PB = SED and SED.PanelBuilder
if not PB then
    ErrorNoHalt("[Rareload] Missing SED.PanelBuilder in SED_panel_builder_collectors.lua\n")
    return
end

local SIMPLE_FIELDS = {
    { "ownership", "OwnerID",        { "ownerSteamID", "RareloadOwnerSteamID" } },
    { "ownership", "OwnerID64",      { "ownerSteamID64", "RareloadOwnerSteamID64" } },
    { "ownership", "Rareload Owner", { "RareloadOwnerSteamID", "RareloadOwnerSteamID64" } },
    { "ownership", "SpawnFlags",     { "spawnflags", "SpawnFlags" } },
    { "ownership", "SpawnedBy",      { "originallySpawnedBy", "OriginalSpawner" } },
    { "visual",    "Skin",          { "skin", "Skin" } },
    { "visual",    "ModelScale",    { "modelScale", "ModelScale" } },
    { "visual",    "RenderMode",    { "renderMode", "RenderMode" } },
    { "visual",    "RenderFX",      { "renderFX", "RenderFx", "RenderFX" } },
    { "visual",    "Material",      { "material", "Material", "materialOverride" } },
}

function PB.populateCategories(ctx)
    local saved = ctx.saved
    local ent = ctx.ent
    local isNPC = ctx.isNPC
    local add = ctx.add

    local function addPrefixedSummaries(cat, prefix, limit, col, summarizeFn)
        local rows = {}
        for k, v in pairs(saved) do
            if type(k) == "string" and k:sub(1, #prefix) == prefix then
                rows[#rows + 1] = { key = k, value = v }
            end
        end

        if #rows == 0 then return end

        table.sort(rows, function(a, b)
            return a.key < b.key
        end)

        local shown = 0
        for _, row in ipairs(rows) do
            if shown >= limit then break end

            if not (type(row.value) == "boolean" and row.value == false) then
                local summary = summarizeFn and summarizeFn(row.value, row.key) or PB.summarizeValueForPanel(row.value)
                if summary and summary ~= "{}" then
                    local label = PB.humanizeKeyLabel(row.key:sub(#prefix + 1))
                    add(cat, label, summary, col)
                    shown = shown + 1
                end
            end
        end

        if #rows > shown then
            add(cat, "+more", ("%d more..."):format(#rows - shown), Color(150, 150, 150))
        end
    end

    local primaryID = PB.firstValue(saved, "id", "RareloadNPCID", "RareloadEntityID", "RareloadID")
    local className = PB.firstValue(saved, "class", "Class", "ClassName", "NPCName", "npcName")
    local displayName = PB.firstValue(saved, "PrintName", "Name", "name")
    local modelPath = PB.firstValue(saved, "Model", "model")
    local ownerValue = PB.firstValue(saved, "owner", "_ownerSteamID", "ownerSteamID", "RareloadOwnerSteamID",
        "ownerSteamID64", "RareloadOwnerSteamID64")
    local spawnTime = PB.firstValue(saved, "spawnTime", "savedAt", "SavedAt")

    add("basic", isNPC and "NPC ID" or "Entity ID", primaryID)
    if saved.RareloadNPCID and saved.RareloadNPCID ~= primaryID then
        add("basic", "Rareload NPC ID", saved.RareloadNPCID)
    end
    if saved.RareloadEntityID and saved.RareloadEntityID ~= primaryID then
        add("basic", "Rareload Entity ID", saved.RareloadEntityID)
    end
    add("basic", "Class", className)
    if saved.ClassName and saved.ClassName ~= className then
        add("basic", "Class Name", saved.ClassName)
    end
    if isNPC then
        add("basic", "NPC Name", PB.firstValue(saved, "NPCName", "npcName"))
    end
    if displayName and displayName ~= className then
        add("basic", "Display Name", displayName)
    end

    if modelPath then
        local modelName = modelPath:match("([^/\\]+)$") or modelPath
        add("basic", "Model", modelName)
    end
    if ownerValue then add("basic", "Owner", ownerValue) end
    if spawnTime then add("basic", "Spawned", os.date("%H:%M:%S", spawnTime)) end

    for _, f in ipairs(SIMPLE_FIELDS) do
        add(f[1], f[2], PB.firstValue(saved, unpack(f[3])))
    end

    local savedPos = PB.firstValue(saved, "pos", "Pos")
    local savedAng = PB.firstValue(saved, "ang", "Angle", "Ang")
    local savedVel = PB.firstValue(saved, "velocity", "Velocity")

    local savedPosText = PB.formatVectorLike(savedPos, 1)
    local savedAngText = PB.formatAngleLike(savedAng, 1)
    local savedVelText = PB.formatVectorLike(savedVel, 1)

    if savedPosText then add("saved", "Saved Position", savedPosText, Color(100, 200, 100)) end
    if savedAngText then add("saved", "Saved Angles", savedAngText, Color(100, 200, 100)) end
    if savedVelText then
        add("saved", "Saved Velocity", savedVelText, Color(150, 150, 200))
    elseif type(savedVel) == "string" then
        add("saved", "Saved Velocity", savedVel, Color(150, 150, 200))
    end

    local savedAt = PB.firstValue(saved, "SavedAt", "savedAt")
    if savedAt then
        add("saved", "Save Timestamp", os.date("%Y-%m-%d %H:%M:%S", savedAt), Color(200, 200, 150))
    end
    if saved.RestoreTime then
        add("saved", "Restore Time", os.date("%Y-%m-%d %H:%M:%S", saved.RestoreTime), Color(200, 200, 150))
    end
    if saved.creationTime then
        add("saved", "Creation Time", string.format("%.2f", saved.creationTime), Color(200, 200, 150))
    end
    add("saved", "Saved By Rareload", PB.yesNo(saved.SavedByRareload), Color(200, 150, 200))
    add("saved", "Saved via Duplicator", PB.yesNo(saved.SavedViaDuplicator), Color(100, 150, 255))
    add("saved", "Spawned By Rareload", PB.yesNo(saved.SpawnedByRareload), Color(120, 180, 255))
    add("saved", "Persistent", PB.yesNo(saved.Persistent), Color(180, 180, 240))

    if saved.physics and istable(saved.physics) then
        local phys = saved.physics
        add("saved", "Physics Exists", PB.yesNo(phys.exists))
        if phys.velocity then add("saved", "Physics Velocity", phys.velocity) end
        add("saved", "Physics Frozen", PB.yesNo(phys.frozen))
        if phys.mass then add("saved", "Physics Mass", phys.mass) end
        if phys.material then add("saved", "Physics Material", phys.material) end
        add("saved", "Gravity Enabled", PB.yesNo(phys.gravityEnabled))
        add("saved", "Motion Enabled", PB.yesNo(phys.motionEnabled))
    end

    if istable(saved.PhysicsObjects) then
        local physObjCount = table.Count(saved.PhysicsObjects)
        add("physics", "Physics Objects", physObjCount)

        local rootPhys = saved.PhysicsObjects[0] or saved.PhysicsObjects["0"] or saved.PhysicsObjects[1]
        if istable(rootPhys) then
            local physPos = PB.formatVectorLike(rootPhys.Pos, 1)
            local physAng = PB.formatAngleLike(rootPhys.Angle, 1)
            if physPos then add("physics", "Phys[0] Pos", physPos) end
            if physAng then add("physics", "Phys[0] Ang", physAng) end
            add("physics", "Phys[0] Frozen", PB.yesNo(rootPhys.Frozen))
            add("physics", "Phys[0] Sleep", PB.yesNo(rootPhys.Sleep))
        end
    end

    local minsText = PB.formatVectorLike(PB.firstValue(saved, "Mins", "mins"), 0)
    local maxsText = PB.formatVectorLike(PB.firstValue(saved, "Maxs", "maxs"), 0)
    if minsText then add("physics", "Mins", minsText) end
    if maxsText then add("physics", "Maxs", maxsText) end

    if isNPC then
        local isVJBase = false
        if IsValid(ent) then
            isVJBase = ((ent.IsVJBaseSNPC == true) or (ent.VJ_ID_Living == true) or (ent.IsVJBaseSNPC_Human == true)) and
            (ent.Base ~= nil)
        else
            isVJBase = (saved.IsVJBaseSNPC == true) or (saved.VJ_ID_Living == true) or (saved.IsVJBaseSNPC_Human == true)
        end

        if isVJBase then
            add("vjbase", "VJ Base NPC", "Detected", Color(100, 255, 150))
            if saved.PrintName and saved.PrintName ~= "" then
                add("vjbase", "Name", saved.PrintName, Color(255, 220, 100))
            end
            if saved.Category and saved.Category ~= "" then
                add("vjbase", "Category", saved.Category, Color(200, 220, 255))
            end
            if saved.Base and saved.Base ~= "" then
                add("vjbase", "Base", saved.Base, Color(180, 200, 220))
            end

            local immunities = {}
            local immunityLabels = {
                Fire = "Fire",
                Bullet = "Bullets",
                Explosive = "Explosives",
                Melee = "Melee",
                Sonic = "Sonic",
                Toxic = "Toxic",
                Electricity = "Electricity",
                Dissolve = "Dissolve"
            }
            for immunityKey, immunityLabel in pairs(immunityLabels) do
                if saved["Immune_" .. immunityKey] then
                    table.insert(immunities, immunityLabel)
                end
            end
            table.sort(immunities)
            if #immunities > 0 then
                add("vjbase", "Immunities", table.concat(immunities, ", "), Color(255, 200, 100))
            end

            if saved.GodMode then add("vjbase", "God Mode", "Active", Color(255, 220, 0)) end
            if saved.IsVJBaseSNPC_Human then add("vjbase", "Type", "Human NPC", Color(255, 180, 120)) end

            if saved.Behavior ~= nil then
                local behaviors = { [0] = "Passive", [1] = "Neutral", [2] = "Aggressive" }
                add("ai", "Behavior", behaviors[saved.Behavior] or tostring(saved.Behavior), Color(255, 200, 150))
            end

            if saved.MovementType ~= nil then
                local moveTypes = { [0] = "Stationary", [1] = "Ground", [2] = "Aerial", [3] = "Aquatic" }
                add("ai", "Movement", moveTypes[saved.MovementType] or tostring(saved.MovementType), Color(150, 255, 200))
            end

            if saved.Alerted then
                add("ai", "Alert Status", "ALERTED", Color(255, 100, 100))
            end
            if saved.Dead then
                add("ai", "Status", "DEAD", Color(255, 50, 50))
            end

            if saved.SightDistance and saved.SightDistance > 0 then
                add("ai", "Sight Range", saved.SightDistance .. " units", Color(150, 220, 255))
            end
            if saved.SightAngle then
                add("ai", "Sight Angle", saved.SightAngle .. "°", Color(150, 200, 255))
            end

            if saved.TurningSpeed and saved.TurningSpeed > 0 then
                add("ai", "Turn Speed", saved.TurningSpeed, Color(200, 200, 255))
            end

            if saved.FollowPlayer then
                add("ai", "Follow Player", saved.IsFollowing and "Yes (Active)" or "Yes (Inactive)",
                    saved.IsFollowing and Color(100, 255, 150) or Color(150, 200, 255))
            end
            if saved.CallForHelp then
                add("ai", "Call For Help", "Enabled", Color(200, 220, 255))
            end
            if saved.CanInvestigate ~= nil then
                add("ai", "Can Investigate", PB.yesNo(saved.CanInvestigate), Color(200, 220, 255))
            end
            if saved.CanOpenDoors ~= nil then
                add("ai", "Can Open Doors", PB.yesNo(saved.CanOpenDoors), Color(200, 220, 255))
            end
            if saved.CanReceiveOrders ~= nil then
                add("ai", "Can Receive Orders", PB.yesNo(saved.CanReceiveOrders), Color(200, 220, 255))
            end
            if saved.AIState ~= nil then
                add("state", "AI State", tostring(saved.AIState), Color(220, 190, 130))
            end

            if saved.Equipment and saved.Equipment ~= "" then
                local weaponName = saved.Equipment:gsub("weapon_", ""):gsub("_", " ")
                add("weapons", "Equipped", weaponName, Color(255, 220, 100))
            end

            if saved.WeaponInventory and istable(saved.WeaponInventory) then
                local invCount = table.Count(saved.WeaponInventory)
                if invCount > 0 then
                    add("weapons", "Inventory", invCount .. " weapons", Color(200, 255, 200))
                    local invList = {}
                    for _, wep in pairs(saved.WeaponInventory) do
                        if type(wep) == "string" and wep ~= "" then
                            invList[#invList + 1] = wep
                        end
                    end
                    table.sort(invList)

                    local limit = 8
                    for i = 1, math.min(#invList, limit) do
                        local wepName = invList[i]:gsub("weapon_", ""):gsub("_", " ")
                        add("weapons", "  " .. i, wepName, Color(180, 220, 255))
                    end
                    if #invList > limit then
                        add("weapons", "  ...", ("+%d more"):format(#invList - limit), Color(150, 150, 150))
                    end
                end
            end

            if saved.Weapon_Accuracy and saved.Weapon_Accuracy > 0 then
                add("weapons", "Accuracy", string.format("%.1f%%", saved.Weapon_Accuracy * 100), Color(200, 255, 200))
            end

            if saved.HasMeleeAttack then
                local dmg = saved.MeleeAttackDamage or "?"
                local dist = saved.MeleeAttackDistance or "?"
                add("combat", "Melee Attack", string.format("DMG:%s  Range:%s", dmg, dist), Color(255, 150, 100))
            end

            if saved.HasGrenadeAttack then
                add("combat", "Grenade Attack", "Available", Color(255, 180, 100))
            end

            if saved.IsMedic then
                local healAmt = saved.Medic_HealAmount or "?"
                add("combat", "Medic", "Heals " .. healAmt .. " HP", Color(100, 255, 150))
            end

            if saved.VJ_NPC_Class and istable(saved.VJ_NPC_Class) then
                local classes = {}
                for _, cls in pairs(saved.VJ_NPC_Class) do
                    if type(cls) == "string" and cls ~= "BaseClass" then
                        table.insert(classes, cls)
                    end
                end
                if #classes > 0 then
                    table.sort(classes)
                    add("relations", "VJ Classes", table.concat(classes, ", "), Color(200, 220, 255))
                end
            end

            local sounds = {}
            if saved.HasIdleSounds then table.insert(sounds, "Idle") end
            if saved.HasAlertSounds then table.insert(sounds, "Alert") end
            if saved.HasPainSounds then table.insert(sounds, "Pain") end
            if saved.HasDeathSounds then table.insert(sounds, "Death") end
            if saved.HasMeleeAttackSounds then table.insert(sounds, "Melee") end
            if saved.HasFootstepSounds then table.insert(sounds, "Footsteps") end
            if #sounds > 0 then
                add("sounds", "Has Sounds", table.concat(sounds, ", "), Color(200, 200, 255))
            end
            if saved.MainSoundPitchValue then
                add("sounds", "Pitch", saved.MainSoundPitchValue, Color(180, 200, 255))
            end

            if saved.BloodColor and saved.BloodColor ~= "" then
                add("visual", "Blood", saved.BloodColor, Color(200, 100, 100))
            end
            if saved.CanGibOnDeath then
                add("visual", "Can Gib", "Yes", Color(255, 150, 100))
            end
        end
    end

    local positionPos = PB.firstValue(saved, "Pos", "pos")
    local positionAng = PB.firstValue(saved, "Angle", "ang", "Ang")
    local positionPosText = PB.formatVectorLike(positionPos, 0)
    local positionAngText = PB.formatAngleLike(positionAng, 0)
    if positionPosText then
        add("position", "Saved Pos", positionPosText, Color(100, 255, 150))
    end
    if positionAngText then
        add("position", "Saved Ang", positionAngText, Color(150, 200, 255))
    end

    if IsValid(ent) then
        local pos = ent:GetPos()
        local ang = ent:GetAngles()
        local vel = ent:GetVelocity()
        add("position", "Live Pos", string.format("%.0f, %.0f, %.0f", pos.x, pos.y, pos.z), Color(255, 200, 100))
        add("position", "Live Ang", string.format("%.0f, %.0f, %.0f", ang.p, ang.y, ang.r), Color(255, 180, 120))
        local speed = math.floor(vel:Length())
        if speed > 0 then
            add("position", "Speed", speed .. " u/s", Color(200, 255, 200))
        end
    end

    local maxHPValue = PB.firstValue(saved, "MaxHealth", "maxHealth", "HealthMax")
    local curHPValue = PB.firstValue(saved, "CurHealth", "health", "Health")
    local startHPValue = PB.firstValue(saved, "StartHealth")
    local maxHP = tonumber(maxHPValue or 0) or 0
    local curHP = tonumber(curHPValue or 0) or 0
    local startHP = tonumber(startHPValue or 0) or 0
    if IsValid(ent) and ent.Health then
        add("state", "Live HP", ent:Health() .. " / " .. maxHP, Color(100, 255, 150))
    end
    if curHP > 0 or maxHP > 0 then
        add("state", "Saved HP", curHP .. " / " .. maxHP, Color(255, 200, 100))
    end
    if startHP > 0 then
        add("state", "Start HP", startHP, Color(255, 230, 140))
    end
    local armorValue = PB.firstValue(saved, "armor", "Armor")
    if armorValue and tonumber(armorValue) and tonumber(armorValue) > 0 then
        add("state", "Armor", armorValue, Color(100, 150, 255))
    end
    if isNPC then
        add("state", "NPC State", PB.firstValue(saved, "npcState", "AIState"))
        add("state", "Hull", PB.firstValue(saved, "hullType", "HullType"))
        add("state", "SchedID", saved.schedule and saved.schedule.id)
        add("state", "Cycle", saved.cycle and string.format("%.2f", saved.cycle))
        add("state", "Seq", saved.sequence)
        add("state", "Playback", saved.playbackRate)
    else
        add("state", "Frozen", PB.yesNo(saved.frozen))
    end

    if isNPC then
        if saved.squad or saved.Squad then add("behavior", "Squad", PB.firstValue(saved, "squad", "Squad")) end
        add("behavior", "Leader", PB.yesNo(saved.squadLeader))
        local targetData = saved.target or saved.Target
        if targetData and targetData.type then
            add("behavior", "Target", targetData.type .. ":" .. (targetData.id or targetData.class or "?"))
        end
        if istable(saved.weapons) then
            local weaponCount = table.Count(saved.weapons)
            if weaponCount > 0 then add("combat", "Weapons", weaponCount) end
            local limit = 16
            local shown = 0
            for i, w in pairs(saved.weapons) do
                if istable(w) then
                    add("combat", "W" .. i, w.class or w.name)
                    shown = shown + 1
                    if shown >= limit then break end
                end
            end
            if weaponCount > limit then
                add("combat", "+more", ("%d more..."):format(weaponCount - limit))
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
        if istable(saved.squadMembers) and table.Count(saved.squadMembers) > 0 then
            add("relations", "SquadMembers", table.Count(saved.squadMembers))
        end
        if saved.vjBaseData and saved.vjBaseData.isVJBaseNPC then
            add("behavior", "VJ Type", saved.vjBaseData.vjType ~= "" and saved.vjBaseData.vjType or "VJBase")
            add("behavior", "RunSpeed", saved.vjBaseData.runSpeed)
        end
    end

    local bodygroups = PB.firstValue(saved, "bodygroups", "BodyGroups")
    local subMaterials = PB.firstValue(saved, "subMaterials", "SubMaterials")
    local colorValue = PB.firstValue(saved, "color", "Color")

    if bodygroups then add("visual", "Bodygroups", table.Count(bodygroups)) end
    local colorTbl = istable(colorValue) and colorValue or nil
    if colorTbl then
        local cr = tonumber(colorTbl.r)
        local cg = tonumber(colorTbl.g)
        local cb = tonumber(colorTbl.b)
        if cr ~= nil and cg ~= nil and cb ~= nil then
            add("visual", "Color", string.format("%d,%d,%d", cr, cg, cb))
        end
    end
    add("visual", "Blood", PB.firstValue(saved, "bloodColor", "BloodColor"))

    local bodygroupsTbl = istable(bodygroups) and bodygroups or nil
    if bodygroupsTbl then
        local count = 0
        local limit = 24
        for k, v in pairs(bodygroupsTbl) do
            add("visual", "BG " .. k, v)
            count = count + 1
            if count >= limit then break end
        end
        if table.Count(bodygroupsTbl) > count then
            add("visual", "+more", ("%d more..."):format(table.Count(bodygroupsTbl) - count))
        end
    end

    local subMaterialsTbl = istable(subMaterials) and subMaterials or nil
    if subMaterialsTbl then
        local count = 0
        local limit = 20
        for idx, mat in pairs(subMaterialsTbl) do
            add("visual", "SubMat" .. idx, mat ~= "" and (mat:match("([^/\\]+)$") or mat) or "<default>")
            count = count + 1
            if count >= limit then break end
        end
        if table.Count(subMaterialsTbl) > count then
            add("visual", "+more", ("%d more..."):format(table.Count(subMaterialsTbl) - count))
        end
    end

    if not isNPC then
        if istable(saved.frozenPhysics) then add("physics", "FrozenPhys", table.Count(saved.frozenPhysics)) end
        if saved.mass then add("physics", "Mass", saved.mass) end
        add("physics", "Solid", PB.firstValue(saved, "solidType", "SolidType"))
        add("physics", "CollGroup", PB.firstValue(saved, "collisionGroup", "ColGroup"))
        if saved.gravity ~= nil then add("physics", "Gravity", saved.gravity and "On" or "Off") end
        if saved.drag ~= nil then add("physics", "Drag", saved.drag and "On" or "Off") end
        if saved.buoyancy ~= nil then add("physics", "Buoyancy", saved.buoyancy) end
        add("physics", "PhysMat", PB.firstValue(saved, "physicsMaterial", "PhysicsMaterial"))
    else
        add("physics", "Hull", PB.firstValue(saved, "hullType", "HullType"))
        add("physics", "CollGroup", PB.firstValue(saved, "collisionGroup", "ColGroup"))
        add("physics", "Solid", PB.firstValue(saved, "solidType", "SolidType"))
    end

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

    if isNPC then
        addPrefixedSummaries("sounds", "SoundTbl_", 24, Color(190, 170, 255), PB.summarizeSoundValueForPanel)
        addPrefixedSummaries("behavior", "AnimTbl_", 18, Color(220, 160, 160))
        addPrefixedSummaries("weapons", "Weapon_", 18, Color(255, 215, 140))
    end

    local metaKeys = {}
    for k in pairs(saved) do
        local keyName = tostring(k)
        local isPrefixed = keyName:sub(1, 9) == "SoundTbl_" or keyName:sub(1, 8) == "AnimTbl_" or
        keyName:sub(1, 7) == "Weapon_"
        if not PB.EXCLUDED_META_KEYS[keyName] and not isPrefixed then
            metaKeys[#metaKeys + 1] = k
        end
    end

    table.sort(metaKeys, function(a, b)
        return tostring(a):lower() < tostring(b):lower()
    end)

    local metaLimit = 45
    local metaAdded = 0
    for _, key in ipairs(metaKeys) do
        if metaAdded >= metaLimit then break end
        local summary = PB.summarizeValueForPanel(saved[key])
        if summary then
            add("meta", PB.humanizeKeyLabel(tostring(key)), summary)
            metaAdded = metaAdded + 1
        end
    end

    if #metaKeys > metaAdded then
        add("meta", "+more", ("%d more..."):format(#metaKeys - metaAdded), Color(150, 150, 150))
    end
end
