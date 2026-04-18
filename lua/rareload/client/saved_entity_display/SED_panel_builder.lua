if SED then
    SED.EntityPanelCache = {}
    SED.NPCPanelCache = {}
end

local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

local CATEGORY_LABEL_ORDER = {
    basic = {
        "NPC ID", "Entity ID", "Rareload NPC ID", "Rareload Entity ID", "Class", "Class Name", "NPC Name",
        "Display Name", "Model", "Owner", "Spawned"
    },
    saved = {
        "Save Timestamp", "Restore Time", "Saved By Rareload", "Saved via Duplicator", "Spawned By Rareload",
        "Persistent", "Creation Time", "Saved Position", "Saved Angles", "Saved Velocity"
    },
    position = { "Saved Pos", "Saved Ang", "Live Pos", "Live Ang", "Speed" },
    state = {
        "Live HP", "Saved HP", "Start HP", "Armor", "AI State", "NPC State", "Hull", "SchedID", "Cycle",
        "Seq", "Playback", "Frozen"
    },
    behavior = {
        "Behavior", "Movement", "Alert Status", "Status", "Follow Player", "Call For Help", "Squad", "Leader",
        "Target"
    },
    combat = { "Melee Attack", "Grenade Attack", "Medic", "Weapons", "Proficiency" },
    visual = { "Skin", "Bodygroups", "ModelScale", "RenderMode", "RenderFX", "Material", "Color", "Blood" },
    physics = {
        "Physics Objects", "Physics Exists", "Physics Velocity", "Physics Frozen", "Physics Mass", "Gravity Enabled",
        "Motion Enabled", "Hull", "CollGroup", "Solid", "SpawnFlags"
    },
    ownership = { "Owner", "OwnerID", "OwnerID64", "Rareload Owner", "SpawnedBy", "SpawnFlags" },
    relations = { "PlayerRel", "Player Rels", "VJ Classes", "SquadMembers" },
    weapons = { "Equipped", "Inventory", "Accuracy" },
    ai = {
        "Behavior", "Movement", "Sight Range", "Sight Angle", "Turn Speed", "Follow Player", "Call For Help",
        "Can Investigate", "Can Open Doors", "Can Receive Orders"
    },
    sounds = { "Has Sounds", "Pitch" },
    vjbase = { "VJ Base NPC", "Name", "Category", "Base", "Type", "Immunities", "God Mode" }
}

local function firstValue(source, ...)
    if not istable(source) then return nil end
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local value = source[key]
        if value ~= nil and value ~= "" then
            return value, key
        end
    end
    return nil
end

local function yesNo(value)
    if value == nil then return nil end
    return value and "Yes" or "No"
end

local FALLBACK_TEXT_COLOR = Color(220, 220, 255)

local function resolveTextColor(value)
    local themeText = SED and SED.THEME and SED.THEME.text
    if RS and RS.safeTextColor then
        local fallback = RS.safeTextColor(themeText, FALLBACK_TEXT_COLOR)
        return RS.safeTextColor(value, fallback)
    end

    if istable(value) and tonumber(value.r) ~= nil and tonumber(value.g) ~= nil and tonumber(value.b) ~= nil then
        return value
    end

    if istable(themeText) and tonumber(themeText.r) ~= nil and tonumber(themeText.g) ~= nil and tonumber(themeText.b) ~= nil then
        return themeText
    end

    return FALLBACK_TEXT_COLOR
end

local function formatVectorLike(value, precision)
    if value == nil then return nil end
    local fmt = "%0." .. tostring(precision or 1) .. "f"
    if isvector and isvector(value) then
        return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value.x, value.y, value.z)
    end
    if istable(value) then
        if value.x ~= nil and value.y ~= nil and value.z ~= nil then
            return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value.x, value.y, value.z)
        end
        if value[1] ~= nil and value[2] ~= nil and value[3] ~= nil then
            return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value[1], value[2], value[3])
        end
    end
    return nil
end

local function formatAngleLike(value, precision)
    if value == nil then return nil end
    local fmt = "%0." .. tostring(precision or 1) .. "f"
    if isangle and isangle(value) then
        return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value.p, value.y, value.r)
    end
    if istable(value) then
        if value.p ~= nil and value.y ~= nil and value.r ~= nil then
            return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value.p, value.y, value.r)
        end
        if value[1] ~= nil and value[2] ~= nil and value[3] ~= nil then
            return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value[1], value[2], value[3])
        end
    end
    return nil
end

local function summarizeValueForPanel(value)
    local valueType = type(value)
    if valueType == "nil" then return nil end
    if valueType == "string" then
        if value == "" then return nil end
        return value
    end
    if valueType == "number" then
        return tostring(value)
    end
    if valueType == "boolean" then
        return value and "Yes" or "No"
    end
    if valueType == "table" then
        local count = table.Count(value)
        if count == 0 then
            return "{}"
        end
        if count <= 6 then
            local preview = {}
            local n = 0
            for k, v in pairs(value) do
                if type(v) == "table" then
                    preview = nil
                    break
                end
                n = n + 1
                preview[#preview + 1] = tostring(k) .. "=" .. tostring(v)
                if n >= 4 then break end
            end
            if preview and #preview > 0 then
                if count > #preview then
                    preview[#preview + 1] = "..."
                end
                return "{" .. table.concat(preview, ", ") .. "}"
            end
        end
        return ("table(%d)"):format(count)
    end
    return tostring(value)
end

local function isLikelySoundPath(value)
    if type(value) ~= "string" then return false end
    local lower = value:lower()
    return lower:find("%.wav$", 1, false) ~= nil or
        lower:find("%.mp3$", 1, false) ~= nil or
        lower:find("%.ogg$", 1, false) ~= nil
end

local function compactSoundPath(path)
    if type(path) ~= "string" or path == "" then return nil end

    local normalized = path:gsub("\\", "/")
    local parts = string.Explode("/", normalized)
    local clean = {}

    for i = 1, #parts do
        if parts[i] ~= "" then
            clean[#clean + 1] = parts[i]
        end
    end

    if #clean == 0 then
        return normalized
    end

    local startIdx = math.max(1, #clean - 2)
    local tail = {}
    for i = startIdx, #clean do
        tail[#tail + 1] = clean[i]
    end

    return table.concat(tail, "/")
end

local function summarizeSoundValueForPanel(value)
    if type(value) == "string" then
        if value == "" then return nil end
        if isLikelySoundPath(value) then
            return compactSoundPath(value)
        end
        return value
    end

    if not istable(value) then
        return summarizeValueForPanel(value)
    end

    local soundItems = {}
    for _, v in pairs(value) do
        if type(v) == "string" and v ~= "" then
            soundItems[#soundItems + 1] = v
        end
    end

    if #soundItems == 0 then
        return summarizeValueForPanel(value)
    end

    table.sort(soundItems)

    local preview = {}
    for i = 1, #soundItems do
        preview[#preview + 1] = "\n  - " .. (compactSoundPath(soundItems[i]) or soundItems[i])
    end

    return string.format("%d sounds:%s", #soundItems, table.concat(preview, ""))
end

local function humanizeKeyLabel(label)
    local text = tostring(label or "")
    if text == "" then return "" end

    text = text:gsub("_", " ")
    text = text:gsub("(%l)(%u)", "%1 %2")
    text = text:gsub("(%u)(%u%l)", "%1 %2")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function sortCategoryLines(list, orderList)
    if not list or #list <= 1 then return end
    local priorities = {}
    if orderList then
        for i, label in ipairs(orderList) do
            priorities[label] = i
        end
    end

    table.sort(list, function(a, b)
        local pa = priorities[a[1]] or 1000
        local pb = priorities[b[1]] or 1000
        if pa ~= pb then return pa < pb end

        local la = tostring(a[1]):lower()
        local lb = tostring(b[1]):lower()
        if la ~= lb then return la < lb end

        return (a[5] or 0) < (b[5] or 0)
    end)
end

function SED.BuildPanelData(saved, ent, isNPC)
    if not saved then return nil end

    SED.EntityPanelCache = SED.EntityPanelCache or {}
    SED.NPCPanelCache = SED.NPCPanelCache or {}

    local panelCache = isNPC and SED.NPCPanelCache or SED.EntityPanelCache
    local fallbackClass = firstValue(saved, "class", "Class", "ClassName", "NPCName", "npcName") or "unknown"
    local fallbackSpawnTime = firstValue(saved, "spawnTime", "savedAt", "SavedAt") or 0
    local id = saved.id or saved.RareloadNPCID or saved.RareloadEntityID or saved.RareloadID or
        (fallbackClass .. "#" .. tostring(fallbackSpawnTime))
    local now = CurTime()
    local entry = panelCache[id]

    if entry and entry.expires > now then
        if IsValid(ent) and entry.data then
            local liveData = entry.data.position
            if liveData then
                local pos = ent:GetPos()
                local ang = ent:GetAngles()
                local vel = ent:GetVelocity()
                local maxHP = firstValue(saved, "MaxHealth", "maxHealth", "StartHealth") or 0

                for i, line in ipairs(liveData) do
                    if line[1] == "Live Pos" then
                        line[2] = string.format("%.0f %.0f %.0f", pos.x, pos.y, pos.z)
                    elseif line[1] == "Live Ang" then
                        line[2] = string.format("%.0f %.0f %.0f", ang.p, ang.y, ang.r)
                    elseif line[1] == "Live Vel" then
                        line[2] = string.format("%.0f %.0f %.0f", vel.x, vel.y, vel.z)
                    elseif line[1] == "Live HP" and ent.Health then
                        line[2] = maxHP > 0 and (ent:Health() .. " / " .. maxHP) or tostring(ent:Health())
                    end
                end
            end
        end
        return entry
    end

    -- for categories not cats like meow meow
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
        vjbase = {},
        weapons = {},
        ai = {},
        sounds = {},
        meta = {}
    }

    local addOrder = 0
    local seenByCategory = {}

    local function add(cat, label, value, col, opts)
        if value == nil or value == "" or not cats[cat] then return end

        local textValue = tostring(value)
        local rowColor = resolveTextColor(col)
        seenByCategory[cat] = seenByCategory[cat] or {}

        local dedupeKey = tostring(label) .. "\31" .. textValue
        if seenByCategory[cat][dedupeKey] then return end
        seenByCategory[cat][dedupeKey] = true

        addOrder = addOrder + 1
        table.insert(cats[cat], { label, textValue, rowColor, opts, addOrder })
    end

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
                local summary = summarizeFn and summarizeFn(row.value, row.key) or summarizeValueForPanel(row.value)
                if summary and summary ~= "{}" then
                    local label = humanizeKeyLabel(row.key:sub(#prefix + 1))
                    add(cat, label, summary, col)
                    shown = shown + 1
                end
            end
        end

        if #rows > shown then
            add(cat, "+more", ("%d more..."):format(#rows - shown), Color(150, 150, 150))
        end
    end

    local primaryID = firstValue(saved, "id", "RareloadNPCID", "RareloadEntityID", "RareloadID")
    local className = firstValue(saved, "class", "Class", "ClassName", "NPCName", "npcName")
    local displayName = firstValue(saved, "PrintName", "Name", "name")
    local modelPath = firstValue(saved, "Model", "model")
    local ownerValue = firstValue(saved, "owner", "_ownerSteamID", "ownerSteamID", "RareloadOwnerSteamID",
        "ownerSteamID64", "RareloadOwnerSteamID64")
    local spawnTime = firstValue(saved, "spawnTime", "savedAt", "SavedAt")

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
        add("basic", "NPC Name", firstValue(saved, "NPCName", "npcName"))
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

    add("ownership", "OwnerID", firstValue(saved, "ownerSteamID", "RareloadOwnerSteamID"))
    add("ownership", "OwnerID64", firstValue(saved, "ownerSteamID64", "RareloadOwnerSteamID64"))
    add("ownership", "Rareload Owner", firstValue(saved, "RareloadOwnerSteamID", "RareloadOwnerSteamID64"))

    local savedPos = firstValue(saved, "pos", "Pos")
    local savedAng = firstValue(saved, "ang", "Angle", "Ang")
    local savedVel = firstValue(saved, "velocity", "Velocity")

    local savedPosText = formatVectorLike(savedPos, 1)
    local savedAngText = formatAngleLike(savedAng, 1)
    local savedVelText = formatVectorLike(savedVel, 1)

    if savedPosText then add("saved", "Saved Position", savedPosText, Color(100, 200, 100)) end
    if savedAngText then add("saved", "Saved Angles", savedAngText, Color(100, 200, 100)) end
    if savedVelText then
        add("saved", "Saved Velocity", savedVelText, Color(150, 150, 200))
    elseif type(savedVel) == "string" then
        add("saved", "Saved Velocity", savedVel, Color(150, 150, 200))
    end

    local savedAt = firstValue(saved, "SavedAt", "savedAt")
    if savedAt then
        add("saved", "Save Timestamp", os.date("%Y-%m-%d %H:%M:%S", savedAt), Color(200, 200, 150))
    end
    if saved.RestoreTime then
        add("saved", "Restore Time", os.date("%Y-%m-%d %H:%M:%S", saved.RestoreTime), Color(200, 200, 150))
    end
    if saved.creationTime then
        add("saved", "Creation Time", string.format("%.2f", saved.creationTime), Color(200, 200, 150))
    end
    if saved.SavedByRareload ~= nil then
        add("saved", "Saved By Rareload", saved.SavedByRareload and "Yes" or "No", Color(200, 150, 200))
    end

    if saved.SavedViaDuplicator ~= nil then
        add("saved", "Saved via Duplicator", saved.SavedViaDuplicator and "Yes" or "No", Color(100, 150, 255))
    end
    if saved.SpawnedByRareload ~= nil then
        add("saved", "Spawned By Rareload", saved.SpawnedByRareload and "Yes" or "No", Color(120, 180, 255))
    end
    if saved.Persistent ~= nil then
        add("saved", "Persistent", saved.Persistent and "Yes" or "No", Color(180, 180, 240))
    end

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

    if istable(saved.PhysicsObjects) then
        local physObjCount = table.Count(saved.PhysicsObjects)
        add("physics", "Physics Objects", physObjCount)

        local rootPhys = saved.PhysicsObjects[0] or saved.PhysicsObjects["0"] or saved.PhysicsObjects[1]
        if istable(rootPhys) then
            local physPos = formatVectorLike(rootPhys.Pos, 1)
            local physAng = formatAngleLike(rootPhys.Angle, 1)
            if physPos then add("physics", "Phys[0] Pos", physPos) end
            if physAng then add("physics", "Phys[0] Ang", physAng) end
            add("physics", "Phys[0] Frozen", yesNo(rootPhys.Frozen))
            add("physics", "Phys[0] Sleep", yesNo(rootPhys.Sleep))
        end
    end

    local minsText = formatVectorLike(firstValue(saved, "Mins", "mins"), 0)
    local maxsText = formatVectorLike(firstValue(saved, "Maxs", "maxs"), 0)
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
                add("ai", "Can Investigate", yesNo(saved.CanInvestigate), Color(200, 220, 255))
            end
            if saved.CanOpenDoors ~= nil then
                add("ai", "Can Open Doors", yesNo(saved.CanOpenDoors), Color(200, 220, 255))
            end
            if saved.CanReceiveOrders ~= nil then
                add("ai", "Can Receive Orders", yesNo(saved.CanReceiveOrders), Color(200, 220, 255))
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

    local positionPos = firstValue(saved, "Pos", "pos")
    local positionAng = firstValue(saved, "Angle", "ang", "Ang")
    local positionPosText = formatVectorLike(positionPos, 0)
    local positionAngText = formatAngleLike(positionAng, 0)
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

    local maxHPValue = firstValue(saved, "MaxHealth", "maxHealth", "HealthMax")
    local curHPValue = firstValue(saved, "CurHealth", "health", "Health")
    local startHPValue = firstValue(saved, "StartHealth")
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
    local armorValue = firstValue(saved, "armor", "Armor")
    if armorValue and tonumber(armorValue) and tonumber(armorValue) > 0 then
        add("state", "Armor", armorValue, Color(100, 150, 255))
    end
    if isNPC then
        add("state", "NPC State", firstValue(saved, "npcState", "AIState"))
        add("state", "Hull", firstValue(saved, "hullType", "HullType"))
        add("state", "SchedID", saved.schedule and saved.schedule.id)
        add("state", "Cycle", saved.cycle and string.format("%.2f", saved.cycle))
        add("state", "Seq", saved.sequence)
        add("state", "Playback", saved.playbackRate)
    else
        add("state", "Frozen", saved.frozen == nil and nil or (saved.frozen and "Yes" or "No"))
    end

    if isNPC then
        if saved.squad or saved.Squad then add("behavior", "Squad", firstValue(saved, "squad", "Squad")) end
        if saved.squadLeader ~= nil then add("behavior", "Leader", saved.squadLeader and "Yes" or "No") end
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

    local bodygroups = firstValue(saved, "bodygroups", "BodyGroups")
    local subMaterials = firstValue(saved, "subMaterials", "SubMaterials")
    local colorValue = firstValue(saved, "color", "Color")

    add("visual", "Skin", firstValue(saved, "skin", "Skin"))
    if bodygroups then add("visual", "Bodygroups", table.Count(bodygroups)) end
    add("visual", "ModelScale", firstValue(saved, "modelScale", "ModelScale"))
    add("visual", "RenderMode", firstValue(saved, "renderMode", "RenderMode"))
    add("visual", "RenderFX", firstValue(saved, "renderFX", "RenderFx", "RenderFX"))
    add("visual", "Material", firstValue(saved, "material", "Material", "materialOverride"))
    local colorTbl = istable(colorValue) and colorValue or nil
    if colorTbl then
        local cr = tonumber(colorTbl.r)
        local cg = tonumber(colorTbl.g)
        local cb = tonumber(colorTbl.b)
        if cr ~= nil and cg ~= nil and cb ~= nil then
            add("visual", "Color", string.format("%d,%d,%d", cr, cg, cb))
        end
    end
    add("visual", "Blood", firstValue(saved, "bloodColor", "BloodColor"))

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
        add("physics", "Solid", firstValue(saved, "solidType", "SolidType"))
        add("physics", "CollGroup", firstValue(saved, "collisionGroup", "ColGroup"))
        if saved.gravity ~= nil then add("physics", "Gravity", saved.gravity and "On" or "Off") end
        if saved.drag ~= nil then add("physics", "Drag", saved.drag and "On" or "Off") end
        if saved.buoyancy ~= nil then add("physics", "Buoyancy", saved.buoyancy) end
        add("physics", "PhysMat", firstValue(saved, "physicsMaterial", "PhysicsMaterial"))
    else
        add("physics", "Hull", firstValue(saved, "hullType", "HullType"))
        add("physics", "CollGroup", firstValue(saved, "collisionGroup", "ColGroup"))
        add("physics", "Solid", firstValue(saved, "solidType", "SolidType"))
    end

    add("ownership", "SpawnFlags", firstValue(saved, "spawnflags", "SpawnFlags"))
    add("ownership", "SpawnedBy", firstValue(saved, "originallySpawnedBy", "OriginalSpawner"))
    add("ownership", "OwnerID", firstValue(saved, "ownerSteamID", "RareloadOwnerSteamID"))

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
        addPrefixedSummaries("sounds", "SoundTbl_", 24, Color(190, 170, 255), summarizeSoundValueForPanel)
        addPrefixedSummaries("behavior", "AnimTbl_", 18, Color(220, 160, 160))
        addPrefixedSummaries("weapons", "Weapon_", 18, Color(255, 215, 140))
    end

    local excludedMetaKeys = {
        _ownerSteamID = true,
        _fromSnapshot = true,
        id = true,
        class = true,
        Class = true,
        ClassName = true,
        NPCName = true,
        npcName = true,
        name = true,
        Name = true,
        PrintName = true,
        model = true,
        Model = true,
        pos = true,
        Pos = true,
        ang = true,
        Angle = true,
        Ang = true,
        velocity = true,
        Velocity = true,
        SavedAt = true,
        savedAt = true,
        spawnTime = true,
        RestoreTime = true,
        creationTime = true,
        SavedByRareload = true,
        SavedViaDuplicator = true,
        SpawnedByRareload = true,
        owner = true,
        ownerSteamID = true,
        ownerSteamID64 = true,
        RareloadOwnerSteamID = true,
        RareloadOwnerSteamID64 = true,
        RareloadNPCID = true,
        RareloadEntityID = true,
        RareloadID = true,
        MaxHealth = true,
        maxHealth = true,
        CurHealth = true,
        Health = true,
        health = true,
        StartHealth = true,
        armor = true,
        Armor = true,
        PhysicsObjects = true,
        physics = true,
        Mins = true,
        Maxs = true,
        mins = true,
        maxs = true,
        bodygroups = true,
        BodyGroups = true,
        subMaterials = true,
        SubMaterials = true,
        color = true,
        Color = true,
        bloodColor = true,
        BloodColor = true,
        collisionGroup = true,
        ColGroup = true,
        solidType = true,
        SolidType = true,
        hullType = true,
        HullType = true,
        spawnflags = true,
        SpawnFlags = true,
        originallySpawnedBy = true,
        OriginalSpawner = true,
        vjBaseData = true,
        VJ_NPC_Class = true,
        weapons = true,
        WeaponInventory = true,
        relations = true,
        target = true,
        Target = true,
        squadMembers = true,
        keyvalues = true,
        keyValues = true
    }

    local metaKeys = {}
    for k in pairs(saved) do
        local keyName = tostring(k)
        local isPrefixed = keyName:sub(1, 9) == "SoundTbl_" or keyName:sub(1, 8) == "AnimTbl_" or
            keyName:sub(1, 7) == "Weapon_"
        if not excludedMetaKeys[keyName] and not isPrefixed then
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
        local summary = summarizeValueForPanel(saved[key])
        if summary then
            add("meta", humanizeKeyLabel(tostring(key)), summary)
            metaAdded = metaAdded + 1
        end
    end

    if #metaKeys > metaAdded then
        add("meta", "+more", ("%d more..."):format(#metaKeys - metaAdded), Color(150, 150, 150))
    end

    local function clampCategory(catId)
        local list = cats[catId]
        if not list then return end
        local maxLines = 200
        if #list > maxLines then
            local extra = #list - maxLines
            while #list > maxLines do table.remove(list) end
            list[#list + 1] = { "+more", ("%d more..."):format(extra), resolveTextColor(nil) }
        end
    end

    for catId, list in pairs(cats) do
        sortCategoryLines(list, CATEGORY_LABEL_ORDER[catId])
        clampCategory(catId)
    end

    local categoryCounts = {}
    for catId, list in pairs(cats) do
        categoryCounts[catId] = #list
    end

    local oldEntry = panelCache[id]
    local oldActiveCat = (oldEntry and oldEntry.activeCat) or "basic"
    local oldAnimTabY = oldEntry and oldEntry.animTabY
    local oldSidebarScroll = oldEntry and oldEntry.sidebarScroll
    local oldCurWidth = oldEntry and oldEntry.curWidth
    local oldCurHeight = oldEntry and oldEntry.curHeight
    local oldMaxLabelWidths = oldEntry and oldEntry.maxLabelWidths
    local oldLod = oldEntry and oldEntry.lod
    local oldWrap = oldEntry and oldEntry._wrap
    local oldWidths = (oldEntry and oldEntry.widths) or {}

    entry = {
        data = cats,
        counts = categoryCounts,
        expires = now + SED.INFO_CACHE_LIFETIME * 2,
        activeCat = oldActiveCat,
        animTabY = oldAnimTabY,
        sidebarScroll = oldSidebarScroll,
        curWidth = oldCurWidth,
        curHeight = oldCurHeight,
        maxLabelWidths = oldMaxLabelWidths,
        lod = oldLod,
        _wrap = oldWrap,
        widths = oldWidths
    }
    panelCache[id] = entry
    return entry
end
