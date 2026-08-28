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
                    local label = RARELOAD.TextUtils.HumanizeKeyLabel(row.key:sub(#prefix + 1))
                    add(cat, label, summary, col)
                    shown = shown + 1
                end
            end
        end

        if #rows > shown then
            local more = RARELOAD and RARELOAD.L and RARELOAD.L("sed.more", #rows - shown)
                or ("%d more..."):format(#rows - shown)
            add(cat, "+more", more, Color(150, 150, 150))
        end
    end

    local primaryID = PB.firstValue(saved, "id", "RareloadNPCID", "RareloadEntityID", "RareloadID")
    local className = PB.firstValue(saved, "class", "Class", "ClassName", "NPCName", "npcName")
    local displayName = PB.firstValue(saved, "PrintName", "Name", "name")
    local modelPath = PB.firstValue(saved, "Model", "model")
    local ownerValue = PB.firstValue(saved, "owner", "_ownerSteamID", "ownerSteamID", "RareloadOwnerSteamID",
        "ownerSteamID64", "RareloadOwnerSteamID64")
    local spawnTime = PB.firstValue(saved, "spawnTime", "savedAt", "SavedAt")

    local isVeh = not isNPC and (
        saved.isVehicle == true or
        (RARELOAD.DataUtils and RARELOAD.DataUtils.ClassLooksLikeVehicle and RARELOAD.DataUtils.ClassLooksLikeVehicle(className)) or
        (isstring(className) and (
            string.find(className, "vehicle") or
            string.find(className, "jeep") or
            string.find(className, "airboat") or
            string.find(className, "^lvs_") or
            string.find(className, "^lfs_") or
            string.find(className, "lunasflightschool") or
            string.find(className, "fphysics") or
            string.find(className, "^wac_") or
            string.find(className, "^glide_") or
            string.find(className, "^sent_sakarias_car")
        )) or
        (IsValid(ent) and (
            (RARELOAD.DataUtils and RARELOAD.DataUtils.IsVehicleEntity and RARELOAD.DataUtils.IsVehicleEntity(ent)) or
            ent:IsVehicle() or ent.LVS or ent.IsLVS or ent.LFS or ent.IsLFS or ent.IsSimfphyscar or ent.IsWAC
        ))
    )

    local isLVS = isVeh and (saved.LVS or saved.IsLVS or (IsValid(ent) and (ent.LVS or ent.IsLVS)) or (className and string.find(className, "^lvs_")) or (saved.Base and string.find(saved.Base, "lvs_")))
    local isLFS = isVeh and (saved.LFS or saved.IsLFS or (IsValid(ent) and (ent.LFS or ent.IsLFS)) or (className and (string.find(className, "^lfs_") or string.find(className, "^lunasflightschool") or string.find(className, "_lfs_"))) or (saved.Base and (string.find(saved.Base, "lunasflightschool") or string.find(saved.Base, "lfs_"))))
    local isSimfphys = isVeh and (saved.IsSimfphyscar or saved.bIsSimfphyscar or (IsValid(ent) and (ent.IsSimfphyscar or ent.bIsSimfphyscar)) or (className and string.find(className, "fphysics")))
    local isWAC = isVeh and (saved.IsWAC or saved.wac_seatinfo ~= nil or (IsValid(ent) and (ent.IsWAC or ent.wac_seatinfo ~= nil)) or (className and string.find(className, "^wac_")))
    local isGlide = isVeh and (saved.IsGlideVehicle or (IsValid(ent) and ent.IsGlideVehicle) or (className and string.find(className, "^glide_")))
    local isSCar = isVeh and (saved.IsSCar or (IsValid(ent) and ent.IsSCar) or (className and string.find(className, "^sent_sakarias_car")))

    add("basic", isNPC and "NPC ID" or (isVeh and "Vehicle ID" or "Entity ID"), primaryID)
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

    if isVeh then
        local frameworkName = isLVS and "[LVS] Luna Vehicle System"
            or (isLFS and "[LFS] Luna's Flight School")
            or (isSimfphys and "[Simfphys] Physics Vehicle")
            or (isWAC and "[WAC] Aircraft")
            or (isGlide and "[Glide] Vehicle")
            or (isSCar and "[SCars] Vehicle")
            or "Source Engine Vehicle"

        add("basic", "Framework", frameworkName, Color(0, 220, 255))

        local typeName = "Vehicle"
        local lowerClass = string.lower(className or "")
        local lowerBase = string.lower(tostring(saved.Base or ""))
        if string.find(lowerClass, "atat") or string.find(lowerClass, "atte") or string.find(lowerClass, "walker") or string.find(lowerBase, "walker") or string.find(lowerBase, "atte") then
            typeName = "Walker / Heavy Armor"
        elseif string.find(lowerClass, "gunship") or string.find(lowerClass, "laat") or string.find(lowerClass, "dropship") then
            typeName = "Gunship / Transport"
        elseif string.find(lowerClass, "starfighter") or string.find(lowerClass, "xwing") or string.find(lowerClass, "tie") or string.find(lowerClass, "fighter") or isLFS then
            typeName = "Starfighter / Aircraft"
        elseif string.find(lowerClass, "speeder") or string.find(lowerClass, "hover") then
            typeName = "Speeder / Hovercraft"
        elseif string.find(lowerClass, "heli") or string.find(lowerClass, "wac_hc") or string.find(lowerClass, "chopper") then
            typeName = "Helicopter"
        elseif string.find(lowerClass, "plane") or string.find(lowerClass, "wac_pl") then
            typeName = "Airplane"
        elseif string.find(lowerClass, "police") or string.find(lowerClass, "cruiser") or string.find(lowerClass, "cop") then
            typeName = "Police / Emergency Vehicle"
        elseif isSimfphys or isGlide or string.find(lowerClass, "car") or string.find(lowerClass, "truck") or string.find(lowerClass, "sedan") then
            typeName = "Automobile / Wheeled Vehicle"
        elseif string.find(lowerClass, "pod") or string.find(lowerClass, "seat") or string.find(lowerClass, "chair") then
            typeName = "Vehicle Pod / Seat"
        end
        add("basic", "Type", typeName, Color(140, 230, 255))

        if saved.Base and saved.Base ~= "" then
            add("basic", "Base", saved.Base, Color(180, 200, 220))
        end
        local vehCat = saved.Category or saved.VehicleCategory
        if vehCat and vehCat ~= "" then
            add("basic", "Category", vehCat, Color(200, 220, 255))
        end
        if saved.VehicleSubCategory and saved.VehicleSubCategory ~= "" then
            add("basic", "SubCategory", saved.VehicleSubCategory, Color(170, 210, 255))
        end
        if saved.Author and saved.Author ~= "" then
            add("basic", "Author", saved.Author, Color(220, 220, 180))
        end
        local vehInfo = saved.Information or saved.Instructions or saved.Purpose
        if vehInfo and vehInfo ~= "" then
            add("basic", "Info", vehInfo, Color(200, 200, 200))
        end
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

    local savedPosText = RARELOAD.DataUtils.FormatVectorLike(savedPos, 1)
    local savedAngText = RARELOAD.DataUtils.FormatAngleLike(savedAng, 1)
    local savedVelText = RARELOAD.DataUtils.FormatVectorLike(savedVel, 1)

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
    add("saved", "Saved By Rareload", RARELOAD.TextUtils.BoolToYesNo(saved.SavedByRareload), Color(200, 150, 200))
    add("saved", "Saved via Duplicator", RARELOAD.TextUtils.BoolToYesNo(saved.SavedViaDuplicator), Color(100, 150, 255))
    add("saved", "Spawned By Rareload", RARELOAD.TextUtils.BoolToYesNo(saved.SpawnedByRareload), Color(120, 180, 255))
    add("saved", "Persistent", RARELOAD.TextUtils.BoolToYesNo(saved.Persistent), Color(180, 180, 240))

    if saved.physics and istable(saved.physics) then
        local phys = saved.physics
        add("saved", "Physics Exists", RARELOAD.TextUtils.BoolToYesNo(phys.exists))
        if phys.velocity then add("saved", "Physics Velocity", phys.velocity) end
        add("saved", "Physics Frozen", RARELOAD.TextUtils.BoolToYesNo(phys.frozen))
        if phys.mass then add("saved", "Physics Mass", phys.mass) end
        if phys.material then add("saved", "Physics Material", phys.material) end
        add("saved", "Gravity Enabled", RARELOAD.TextUtils.BoolToYesNo(phys.gravityEnabled))
        add("saved", "Motion Enabled", RARELOAD.TextUtils.BoolToYesNo(phys.motionEnabled))
    end

    if istable(saved.PhysicsObjects) then
        local physObjCount = table.Count(saved.PhysicsObjects)
        add("physics", "Physics Objects", physObjCount)

        local rootPhys = saved.PhysicsObjects[0] or saved.PhysicsObjects["0"] or saved.PhysicsObjects[1]
        if istable(rootPhys) then
            local physPos = RARELOAD.DataUtils.FormatVectorLike(rootPhys.Pos, 1)
            local physAng = RARELOAD.DataUtils.FormatAngleLike(rootPhys.Angle, 1)
            if physPos then add("physics", "Phys[0] Pos", physPos) end
            if physAng then add("physics", "Phys[0] Ang", physAng) end
            add("physics", "Phys[0] Frozen", RARELOAD.TextUtils.BoolToYesNo(rootPhys.Frozen))
            add("physics", "Phys[0] Sleep", RARELOAD.TextUtils.BoolToYesNo(rootPhys.Sleep))
        end
    end

    local minsText = RARELOAD.DataUtils.FormatVectorLike(PB.firstValue(saved, "Mins", "mins"), 0)
    local maxsText = RARELOAD.DataUtils.FormatVectorLike(PB.firstValue(saved, "Maxs", "maxs"), 0)
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
                add("ai", "Can Investigate", RARELOAD.TextUtils.BoolToYesNo(saved.CanInvestigate), Color(200, 220, 255))
            end
            if saved.CanOpenDoors ~= nil then
                add("ai", "Can Open Doors", RARELOAD.TextUtils.BoolToYesNo(saved.CanOpenDoors), Color(200, 220, 255))
            end
            if saved.CanReceiveOrders ~= nil then
                add("ai", "Can Receive Orders", RARELOAD.TextUtils.BoolToYesNo(saved.CanReceiveOrders), Color(200, 220, 255))
            end
            if saved.AIState ~= nil then
                add("state", "AI State", tostring(saved.AIState), Color(220, 190, 130))
            end

            if saved.Equipment and saved.Equipment ~= "" then
                local weaponName = RARELOAD.TextUtils.CompactWeaponClassName(saved.Equipment)
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
                        local wepName = RARELOAD.TextUtils.CompactWeaponClassName(invList[i])
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
    local positionPosText = RARELOAD.DataUtils.FormatVectorLike(positionPos, 0)
    local positionAngText = RARELOAD.DataUtils.FormatAngleLike(positionAng, 0)
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

    if isVeh then
        local dt = saved.DT or saved.dt or {}
        local physObjs = saved.PhysicsObjects or {}
        local rootPhys = physObjs[0] or physObjs["0"] or physObjs[1] or {}

        -- Framework Name
        local frameworkName = isLVS and "[LVS] Luna Vehicle System"
            or (isLFS and "[LFS] Luna's Flight School")
            or (isSimfphys and "[Simfphys] Physics Vehicle")
            or (isWAC and "[WAC] Aircraft")
            or (isGlide and "[Glide] Vehicle")
            or (isSCar and "[SCars] Vehicle")
            or "Source Engine Vehicle"

        -- Vehicle Type Classification
        local typeName = "Vehicle"
        local lowerClass = string.lower(className or "")
        local lowerBase = string.lower(tostring(saved.Base or ""))
        if string.find(lowerClass, "atat") or string.find(lowerClass, "atte") or string.find(lowerClass, "walker") or string.find(lowerBase, "walker") or string.find(lowerBase, "atte") then
            typeName = "Walker / Heavy Armor"
        elseif string.find(lowerClass, "gunship") or string.find(lowerClass, "laat") or string.find(lowerClass, "dropship") then
            typeName = "Gunship / Transport"
        elseif string.find(lowerClass, "starfighter") or string.find(lowerClass, "xwing") or string.find(lowerClass, "tie") or string.find(lowerClass, "fighter") or isLFS then
            typeName = "Starfighter / Aircraft"
        elseif string.find(lowerClass, "speeder") or string.find(lowerClass, "hover") then
            typeName = "Speeder / Hovercraft"
        elseif string.find(lowerClass, "heli") or string.find(lowerClass, "wac_hc") or string.find(lowerClass, "chopper") then
            typeName = "Helicopter"
        elseif string.find(lowerClass, "plane") or string.find(lowerClass, "wac_pl") then
            typeName = "Airplane"
        elseif string.find(lowerClass, "police") or string.find(lowerClass, "cruiser") or string.find(lowerClass, "cop") then
            typeName = "Police / Emergency Vehicle"
        elseif isSimfphys or isGlide or string.find(lowerClass, "car") or string.find(lowerClass, "truck") or string.find(lowerClass, "sedan") then
            typeName = "Automobile / Wheeled Vehicle"
        elseif string.find(lowerClass, "pod") or string.find(lowerClass, "seat") or string.find(lowerClass, "chair") then
            typeName = "Vehicle Pod / Seat"
        end

        local vehCat = saved.Category or saved.VehicleCategory

        -- ====================================================================
        -- CATEGORY: VEHICLE SPECIFICATIONS & AERODYNAMICS
        -- ====================================================================
        add("vehicle", "Framework", frameworkName, Color(0, 220, 255))
        add("vehicle", "Type", typeName, Color(140, 230, 255))
        if displayName and displayName ~= "" then
            add("vehicle", "Display Name", displayName, Color(255, 220, 100))
        end
        if vehCat and vehCat ~= "" then
            add("vehicle", "Category", vehCat, Color(200, 220, 255))
        end
        if saved.VehicleSubCategory and saved.VehicleSubCategory ~= "" then
            add("vehicle", "SubCategory", saved.VehicleSubCategory, Color(170, 210, 255))
        end
        if saved.Author and saved.Author ~= "" then
            add("vehicle", "Author", saved.Author, Color(220, 220, 180))
        end

        local topSpeed = saved.MaxVelocity or saved.MaxSpeed or saved.maxspeed or saved.TopSpeed or (saved.Walkspeed and saved.Sprintspeed and (saved.Sprintspeed * 10))
        if topSpeed and tonumber(topSpeed) and tonumber(topSpeed) > 0 then
            local numSpeed = tonumber(topSpeed)
            local kmh = math.Round(numSpeed * 0.06858)
            local mph = math.Round(numSpeed * 0.04261)
            add("vehicle", "Top Speed", string.format("%d u/s (%d km/h / %d mph)", numSpeed, kmh, mph), Color(100, 255, 150))
        end

        if saved.Sprintspeed and saved.Walkspeed then
            add("vehicle", "Speeds", string.format("Walk: %d | Sprint: %d", saved.Walkspeed, saved.Sprintspeed), Color(180, 255, 180))
        end

        if saved.MaxThrust and tonumber(saved.MaxThrust) and tonumber(saved.MaxThrust) > 0 then
            add("vehicle", "Max Thrust", tostring(saved.MaxThrust) .. " N", Color(255, 200, 100))
        end
        if saved.ThrustVtol and tonumber(saved.ThrustVtol) and tonumber(saved.ThrustVtol) > 0 then
            add("vehicle", "VTOL Thrust", tostring(saved.ThrustVtol) .. " N", Color(255, 180, 120))
        end

        if saved.TurnRatePitch or saved.TurnRateYaw or saved.TurnRateRoll then
            local p = saved.TurnRatePitch and tostring(saved.TurnRatePitch) .. "°" or "-"
            local y = saved.TurnRateYaw and tostring(saved.TurnRateYaw) .. "°" or "-"
            local r = saved.TurnRateRoll and tostring(saved.TurnRateRoll) .. "°" or "-"
            add("vehicle", "Flight Turn Rate", string.format("P: %s  Y: %s  R: %s", p, y, r), Color(150, 220, 255))
        elseif saved.Turnrate and tonumber(saved.Turnrate) and tonumber(saved.Turnrate) > 0 then
            add("vehicle", "Turn Rate", tostring(saved.Turnrate) .. "°/s", Color(150, 220, 255))
        end

        if saved.HeadTurnrate and tonumber(saved.HeadTurnrate) and tonumber(saved.HeadTurnrate) > 0 then
            add("vehicle", "Head Turn Rate", tostring(saved.HeadTurnrate) .. "°/s", Color(180, 220, 255))
        end

        if saved.MaxPitch or saved.MaxRoll then
            local mp = saved.MaxPitch and (tostring(saved.MaxPitch) .. "°") or "-"
            local mr = saved.MaxRoll and (tostring(saved.MaxRoll) .. "°") or "-"
            add("vehicle", "Max Pitch / Roll", string.format("Pitch: %s | Roll: %s", mp, mr), Color(200, 200, 255))
        end

        if saved.TipOverThreashold and istable(saved.TipOverThreashold) then
            local tp = saved.TipOverThreashold.pitch or "?"
            local tr = saved.TipOverThreashold.roll or "?"
            add("vehicle", "Tip Threshold", string.format("Pitch: %s° | Roll: %s°", tp, tr), Color(255, 160, 120))
        end

        local vehMass = saved.Mass or (saved.physics and saved.physics.mass) or (rootPhys and rootPhys.Mass)
        if vehMass and tonumber(vehMass) and tonumber(vehMass) > 0 then
            add("vehicle", "Vehicle Mass", string.format("%s kg", string.Comma(math.floor(tonumber(vehMass)))), Color(200, 220, 255))
        end

        -- ====================================================================
        -- CATEGORY: DRIVETRAIN & ENGINE
        -- ====================================================================
        local engineActive = (dt.EngineActive ~= nil and dt.EngineActive)
            or (saved.EngineActive ~= nil and saved.EngineActive)
            or (dt.Active ~= nil and dt.Active)
            or (saved.Active ~= nil and saved.Active)
        if engineActive ~= nil then
            add("drivetrain", "Engine", engineActive and "RUNNING" or "OFF", engineActive and Color(100, 255, 150) or Color(255, 100, 100))
        end

        local curRPM = dt.RPM or saved.RPM or (dt.CurrentRPM or saved.CurrentRPM)
        local idleRPM = saved.IdleRPM or dt.MinRPM or saved.MinRPM
        local limitRPM = saved.LimitRPM or saved.MaxRPM or dt.MaxRPM
        if curRPM and tonumber(curRPM) then
            add("drivetrain", "Current RPM", string.format("%d RPM", math.floor(tonumber(curRPM))), Color(255, 220, 100))
        end
        if idleRPM or limitRPM then
            local idText = idleRPM and tostring(math.floor(tonumber(idleRPM))) or "?"
            local limText = limitRPM and tostring(math.floor(tonumber(limitRPM))) or "?"
            add("drivetrain", "RPM Range", string.format("%s - %s RPM", idText, limText), Color(200, 255, 200))
        end

        local throttle = dt.NWThrottle or dt.Throttle or (dt.Move and math.abs(dt.Move))
        if throttle and tonumber(throttle) then
            local thrPct = math.Clamp(math.floor(tonumber(throttle) * (tonumber(throttle) <= 1 and 100 or 1)), 0, 100)
            add("drivetrain", "Live Throttle", tostring(thrPct) .. "%", Color(255, 220, 100))
        end

        if saved.ThrottleRateUp or saved.ThrottleRateDown then
            local up = saved.ThrottleRateUp and tostring(saved.ThrottleRateUp) or "?"
            local dn = saved.ThrottleRateDown and tostring(saved.ThrottleRateDown) or "?"
            add("drivetrain", "Throttle Rates", string.format("Up: %s/s | Down: %s/s", up, dn), Color(180, 220, 200))
        end

        -- Transmission & Gears
        local curGear = dt.Gear or dt.RGear or dt.LGear or saved.Gear
        local gears = saved.Gears or saved.ForwardGears
        if curGear ~= nil or gears ~= nil then
            local gText = (curGear and ("Gear " .. tostring(curGear)) or "Neutral") .. (gears and (" (of " .. tostring(gears) .. ")") or "")
            add("drivetrain", "Gears", gText, Color(200, 200, 255))
        end

        local powerDist = dt.PowerDistribution or saved.PowerDistribution
        if powerDist and tonumber(powerDist) then
            local pd = tonumber(powerDist)
            local pLayout = (pd < -0.1 and string.format("AWD (%.0f%% Rear / %.0f%% Front)", (1 + pd) * 100, (-pd) * 100))
                or (pd > 0.1 and string.format("FWD (%.0f%% Front)", pd * 100))
                or "RWD (100% Rear)"
            add("drivetrain", "Power Layout", pLayout, Color(150, 220, 255))
        end

        local diffRatio = dt.DifferentialRatio or saved.DifferentialRatio
        local transEff = dt.TransmissionEfficiency or saved.TransmissionEfficiency
        if diffRatio or transEff then
            local dr = diffRatio and string.format("%.2f Ratio", tonumber(diffRatio)) or ""
            local te = transEff and string.format("%.0f%% Eff", tonumber(transEff) * 100) or ""
            add("drivetrain", "Differential", dr .. (dr ~= "" and te ~= "" and " | " or "") .. te, Color(200, 220, 255))
        end

        if dt.FastTransmission ~= nil or saved.FastTransmission ~= nil then
            local ft = (dt.FastTransmission ~= nil and dt.FastTransmission) or saved.FastTransmission
            add("drivetrain", "Fast Shift", ft and "Enabled" or "Standard", ft and Color(100, 255, 150) or Color(180, 180, 180))
        end

        if saved.HorsePower and tonumber(saved.HorsePower) and tonumber(saved.HorsePower) > 0 then
            add("drivetrain", "Horse Power", tostring(saved.HorsePower) .. " HP", Color(255, 150, 100))
        end

        local peakTorque = saved.PeakTorque or dt.MaxRPMTorque or saved.MaxRPMTorque
        if peakTorque and tonumber(peakTorque) and tonumber(peakTorque) > 0 then
            add("drivetrain", "Peak Torque", tostring(math.floor(tonumber(peakTorque))) .. " Nm", Color(255, 180, 100))
        end

        if dt.MinRPMTorque and dt.MaxRPMTorque then
            add("drivetrain", "RPM Torque", string.format("%d - %d Nm", math.floor(dt.MinRPMTorque), math.floor(dt.MaxRPMTorque)), Color(255, 200, 140))
        end

        local turbo = dt.TurboCharged ~= nil and dt.TurboCharged or saved.TurboCharged
        if turbo ~= nil then
            add("drivetrain", "Turbo / Boost", turbo and "Supercharged / Turbo" or "Naturally Aspirated", turbo and Color(255, 150, 50) or Color(180, 180, 180))
        end

        local brakePower = dt.BrakePower or saved.BrakePower
        if brakePower and tonumber(brakePower) and tonumber(brakePower) > 0 then
            add("drivetrain", "Brake Power", tostring(brakePower) .. " N", Color(255, 120, 120))
        end

        local steerAng = saved.SteerAngle or (dt.MaxSteerAngle and math.floor(dt.MaxSteerAngle))
        if steerAng and tonumber(steerAng) and tonumber(steerAng) > 0 then
            add("drivetrain", "Steer Angle", tostring(steerAng) .. "°", Color(150, 200, 255))
        end

        if dt.CounterSteer and tonumber(dt.CounterSteer) and tonumber(dt.CounterSteer) > 0 then
            add("drivetrain", "Counter Steer", string.format("%.2f Assist", dt.CounterSteer), Color(180, 220, 255))
        end

        if dt.SteerConeMaxSpeed or dt.SteerConeChangeRate then
            local spd = dt.SteerConeMaxSpeed and (tostring(dt.SteerConeMaxSpeed) .. " u/s") or "-"
            local rate = dt.SteerConeChangeRate and (tostring(dt.SteerConeChangeRate) .. "°/s") or "-"
            add("drivetrain", "Steer Cone", string.format("Speed: %s | Rate: %s", spd, rate), Color(170, 210, 255))
        end

        local fuel = saved.Fuel or saved.fuel or dt.Fuel
        local maxFuel = saved.MaxFuel or saved.maxFuel or saved.FuelTankSize
        if fuel or maxFuel then
            local fVal = fuel and tonumber(fuel) and math.floor(tonumber(fuel)) or (fuel and tostring(fuel) or "?")
            local mfVal = maxFuel and tonumber(maxFuel) and math.floor(tonumber(maxFuel)) or (maxFuel and tostring(maxFuel) or "")
            local fText = tostring(fVal) .. (mfVal ~= "" and (" / " .. tostring(mfVal)) or "") .. " L"
            add("drivetrain", "Fuel Capacity", fText, Color(255, 220, 100))
        end

        -- ====================================================================
        -- CATEGORY: COMBAT, WEAPONS & DEFENSE
        -- ====================================================================
        local curHP = tonumber(saved.CurHealth or saved.health or (dt and dt.HP) or 0) or 0
        local maxHP = tonumber(saved.MaxHealth or saved.maxHealth or saved._DuplicatorRestoreMaxHealthTo or 0) or 0
        if curHP > 0 or maxHP > 0 then
            add("combat", "Hull Integrity", string.format("%s / %s HP", string.Comma(curHP), string.Comma(maxHP)), Color(100, 255, 150))
        end

        local shield = dt.Shield or saved.Shield or saved.CurShield
        local maxShield = saved.MaxShield or saved.maxShield
        if (shield and tonumber(shield) and tonumber(shield) > 0) or (maxShield and tonumber(maxShield) and tonumber(maxShield) > 0) then
            local sText = tostring(shield or 0) .. " / " .. tostring(maxShield or 0) .. " HP"
            add("combat", "Deflector Shield", sText, Color(100, 220, 255))
            if saved.ShieldRechargeRate and tonumber(saved.ShieldRechargeRate) and tonumber(saved.ShieldRechargeRate) > 0 then
                local delay = saved.ShieldRechargeDelay and (" (Delay: " .. tostring(saved.ShieldRechargeDelay) .. "s)") or ""
                add("combat", "Shield Recharge", tostring(saved.ShieldRechargeRate) .. " HP/s" .. delay, Color(150, 220, 255))
            end
        end

        local ammoPri = dt.AmmoPrimary or saved.AmmoPrimary or saved.PrimaryAmmo
        local maxAmmoPri = saved.MaxPrimaryAmmo
        if ammoPri ~= nil then
            local priText = tostring(ammoPri) .. (maxAmmoPri and (" / " .. tostring(maxAmmoPri)) or "") .. " rounds"
            add("combat", "Primary Ammo", priText, Color(255, 200, 100))
        end

        local ammoSec = dt.AmmoSecondary or saved.AmmoSecondary or saved.SecondaryAmmo
        local maxAmmoSec = saved.MaxSecondaryAmmo
        if ammoSec ~= nil then
            local secText = tostring(ammoSec) .. (maxAmmoSec and (" / " .. tostring(maxAmmoSec)) or "") .. " rounds"
            add("combat", "Secondary Ammo", secText, Color(255, 160, 100))
        end

        local curWeapon = dt.SelectedWeapon or saved.SelectedWeapon
        if curWeapon then
            add("combat", "Weapon Slot", "Slot " .. tostring(curWeapon) .. " (Active)", Color(255, 220, 120))
        end

        local heat = dt.NWHeat or saved.NWHeat
        if heat and tonumber(heat) then
            local heatVal = math.floor(tonumber(heat))
            local isOverheated = dt.NWOverheated == true
            local heatColor = isOverheated and Color(255, 50, 50) or (heatVal > 60 and Color(255, 150, 50) or Color(150, 220, 255))
            local heatText = isOverheated and string.format("OVERHEATED! (%d%%)", heatVal) or string.format("%d%% Heat", heatVal)
            add("combat", "Weapon Heat", heatText, heatColor)
        end

        if dt.TurretHeat and tonumber(dt.TurretHeat) and tonumber(dt.TurretHeat) > 0 then
            add("combat", "Turret Heat", string.format("%d%% Heat", math.floor(dt.TurretHeat)), Color(255, 180, 100))
        end

        if saved.DSArmorDamageReduction and tonumber(saved.DSArmorDamageReduction) and tonumber(saved.DSArmorDamageReduction) > 0 then
            local redPercent = math.floor((1 - saved.DSArmorDamageReduction) * 100)
            add("combat", "Armor Reduction", tostring(redPercent) .. "% Reduced Damage", Color(100, 255, 150))
        end
        if saved.DSArmorBulletPenetrationAdd and tonumber(saved.DSArmorBulletPenetrationAdd) and tonumber(saved.DSArmorBulletPenetrationAdd) > 0 then
            add("combat", "Penetration Res", "+" .. tostring(saved.DSArmorBulletPenetrationAdd) .. " mm Armor", Color(150, 255, 180))
        end

        if saved.ExplosionDamageOnly ~= nil then
            add("combat", "Damage Filter", saved.ExplosionDamageOnly and "Explosives Only (Immune to Bullets)" or "Standard", Color(255, 180, 120))
        end

        if dt.lvsLockedStatus ~= nil then
            add("combat", "Radar Lock", dt.lvsLockedStatus and "LOCKED ON TARGET" or "Clear",
                dt.lvsLockedStatus and Color(255, 50, 50) or Color(100, 255, 150))
        end

        if saved.MissileAlert ~= nil then
            local dist = saved.MissileAlertDistance and (" (" .. math.floor(saved.MissileAlertDistance) .. " units)") or ""
            add("combat", "Missile Warning", saved.MissileAlert and ("Active Warning" .. dist) or "Disabled",
                saved.MissileAlert and Color(255, 100, 100) or Color(150, 150, 150))
        end

        if dt.AITEAM ~= nil or saved.AITEAM ~= nil then
            local teamId = dt.AITEAM or saved.AITEAM
            local teamNames = { [0] = "Neutral", [1] = "Friendly / Rebel Alliance", [2] = "Hostile / Galactic Empire" }
            add("combat", "AI Allegiance", teamNames[teamId] or ("Team " .. tostring(teamId)), Color(200, 200, 255))
        end

        if dt.AIGunners ~= nil then
            add("combat", "AI Gunners", dt.AIGunners and "Active (Auto-Targeting)" or "Disabled",
                dt.AIGunners and Color(100, 255, 150) or Color(180, 180, 180))
        end
        if dt.AI ~= nil then
            add("combat", "AI Autopilot", dt.AI and "Active (Autonomous Flying)" or "Disabled",
                dt.AI and Color(100, 255, 150) or Color(180, 180, 180))
        end

        -- ====================================================================
        -- CATEGORY: SYSTEMS, CREW, SUSPENSION & UTILITY
        -- ====================================================================
        if IsValid(ent) then
            if ent.GetDriver and isfunction(ent.GetDriver) then
                local driver = ent:GetDriver()
                if IsValid(driver) and driver:IsPlayer() then
                    add("systems", "Driver / Pilot", driver:Nick() .. " (Seated)", Color(100, 255, 150))
                else
                    add("systems", "Driver / Pilot", "Empty (Unoccupied)", Color(180, 180, 180))
                end
            end
            if ent.GetGunnerSeat and isfunction(ent.GetGunnerSeat) then
                local ok, gs = pcall(ent.GetGunnerSeat, ent)
                if ok and IsValid(gs) and gs:IsVehicle() then
                    local gDriver = gs:GetDriver()
                    add("systems", "Gunner Seat", (IsValid(gDriver) and gDriver:IsPlayer()) and (gDriver:Nick() .. " (Seated)") or "Empty",
                        (IsValid(gDriver) and gDriver:IsPlayer()) and Color(100, 255, 150) or Color(180, 180, 180))
                end
            end
            if ent.GetPassengerSeats and isfunction(ent.GetPassengerSeats) then
                local ok, seats = pcall(ent.GetPassengerSeats, ent)
                if ok and istable(seats) then
                    local totalSeats = #seats
                    local occupied = 0
                    for _, s in pairs(seats) do
                        if IsValid(s) and IsValid(s:GetDriver()) then occupied = occupied + 1 end
                    end
                    add("systems", "Passenger Capacity", string.format("%d / %d Occupied", occupied, totalSeats), Color(180, 220, 255))
                end
            end
        end

        -- Suspension
        local suspLength = dt.SuspensionLength or saved.SuspensionLength
        local springStr = dt.SpringStrength or saved.SpringStrength
        local springDamp = dt.SpringDamper or saved.SpringDamper
        if suspLength then
            add("systems", "Suspension", string.format("%.1f in Travel", tonumber(suspLength)), Color(150, 220, 255))
        end
        if springStr or springDamp then
            local ss = springStr and string.format("%.0f N/m", tonumber(springStr)) or ""
            local sd = springDamp and string.format("%.0f Ns/m", tonumber(springDamp)) or ""
            add("systems", "Spring / Damper", ss .. (ss ~= "" and sd ~= "" and " | " or "") .. sd, Color(170, 210, 255))
        end

        -- Wheels & Tires
        local wheelRad = saved.WheelRadius or dt.WheelRadius
        if wheelRad then
            local rText = istable(wheelRad) and (tostring(wheelRad[1] or "?") .. " in (x" .. #wheelRad .. " wheels)") or (tostring(wheelRad) .. " in")
            add("systems", "Wheel / Tire Size", rText, Color(200, 220, 255))
        end

        local fwdTrac = dt.ForwardTractionMax or saved.ForwardTractionMax
        local sideTracMax = dt.SideTractionMax or saved.SideTractionMax
        if fwdTrac or sideTracMax then
            local ft = fwdTrac and ("Fwd: " .. tostring(fwdTrac)) or ""
            local st = sideTracMax and ("Side: " .. tostring(sideTracMax)) or ""
            add("systems", "Tire Traction", ft .. (ft ~= "" and st ~= "" and " | " or "") .. st, Color(180, 220, 255))
        end

        if dt.TireSmokeColor and istable(dt.TireSmokeColor) then
            local tsc = dt.TireSmokeColor
            add("systems", "Tire Smoke Color", string.format("R:%.2f G:%.2f B:%.2f", tsc.x or 0, tsc.y or 0, tsc.z or 0), Color(200, 200, 200))
        end

        -- Lighting & Siren
        local lightsActive = dt.LightsActive ~= nil and dt.LightsActive or saved.LightsActive
        if lightsActive ~= nil then
            add("systems", "Headlights", lightsActive and "ON" or "OFF", lightsActive and Color(255, 255, 150) or Color(150, 150, 150))
        end
        if dt.HeadlightColor and istable(dt.HeadlightColor) then
            local hlc = dt.HeadlightColor
            add("systems", "Light Color", string.format("R:%.2f G:%.2f B:%.2f", hlc.x or 0, hlc.y or 0, hlc.z or 0), Color(255, 255, 200))
        end

        -- Doors & Hatches
        if dt.DoorMode ~= nil then
            add("systems", "Door Mode", "Mode " .. tostring(dt.DoorMode), Color(180, 200, 220))
        end
        if dt.RearHatch ~= nil then
            add("systems", "Rear Hatch", dt.RearHatch and "Open" or "Closed", dt.RearHatch and Color(255, 200, 100) or Color(180, 180, 180))
        end

        -- Walker Specific Parameters
        if saved.HeadTurnRange and istable(saved.HeadTurnRange) then
            local hx = saved.HeadTurnRange.x or 0
            local hy = saved.HeadTurnRange.y or 0
            add("systems", "Head Turn Limits", string.format("Pitch: ±%d° | Yaw: ±%d°", hx, hy), Color(200, 220, 255))
        end
        if saved.floorOffsetPose and istable(saved.floorOffsetPose) then
            local fop = saved.floorOffsetPose
            add("systems", "Leg Floor Offset", string.format("FL:%.1f FR:%.1f RL:%.1f RR:%.1f", fop.fl or 0, fop.fr or 0, fop.rl or 0, fop.rr or 0), Color(180, 220, 255))
        end

        -- Utility & Cargo
        if saved.LAATC_PICKUPABLE ~= nil then
            add("systems", "LAAT/c Carrier", saved.LAATC_PICKUPABLE and "Pickup Compatible" or "Incompatible", saved.LAATC_PICKUPABLE and Color(100, 255, 150) or Color(180, 180, 180))
        end

        if saved.MaintenanceTime and tonumber(saved.MaintenanceTime) and tonumber(saved.MaintenanceTime) > 0 then
            local prog = dt.MaintenanceProgress and string.format(" (Progress: %d%%)", math.floor(dt.MaintenanceProgress)) or ""
            add("systems", "Field Repairs", string.format("%ds time / %d HP repair%s", saved.MaintenanceTime, saved.MaintenanceRepairAmount or 0, prog), Color(150, 255, 200))
        end
    end

    local maxHPValue = PB.firstValue(saved, "MaxHealth", "maxHealth", "HealthMax", "_DuplicatorRestoreMaxHealthTo")
    local curHPValue = PB.firstValue(saved, "CurHealth", "health", "Health")
    if isVeh and saved.DT and saved.DT.HP then
        curHPValue = saved.DT.HP
    end
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

    if isVeh then
        local dt = saved.DT or saved.dt or {}
        if dt.EngineActive ~= nil or saved.EngineActive ~= nil then
            local active = (dt.EngineActive ~= nil and dt.EngineActive) or (saved.EngineActive ~= nil and saved.EngineActive)
            add("state", "Engine", active and "RUNNING" or "OFF", active and Color(100, 255, 150) or Color(200, 150, 150))
        end

        if dt.NWThrottle ~= nil then
            local thr = math.floor((dt.NWThrottle or 0) * 100)
            add("state", "Throttle", tostring(thr) .. "%", Color(255, 220, 100))
        end

        if dt.NWHeat ~= nil then
            local heatColor = dt.NWOverheated and Color(255, 50, 50) or (dt.NWHeat > 50 and Color(255, 150, 50) or Color(150, 220, 255))
            local heatText = dt.NWOverheated and ("OVERHEATED (" .. tostring(dt.NWHeat) .. ")") or tostring(dt.NWHeat)
            add("state", "Heat", heatText, heatColor)
        end

        if dt.LightsActive ~= nil then
            add("state", "Lights", dt.LightsActive and "ON" or "OFF", dt.LightsActive and Color(255, 255, 150) or Color(150, 150, 150))
        end

        if dt.DoorMode ~= nil then
            add("state", "Doors", "Mode " .. tostring(dt.DoorMode), Color(180, 200, 220))
        end
        if dt.RearHatch ~= nil then
            add("state", "Rear Hatch", dt.RearHatch and "Open" or "Closed", dt.RearHatch and Color(255, 200, 100) or Color(180, 180, 180))
        end

        if IsValid(ent) then
            if ent.GetDriver and isfunction(ent.GetDriver) then
                local driver = ent:GetDriver()
                if IsValid(driver) and driver:IsPlayer() then
                    add("state", "Driver", driver:Nick(), Color(100, 255, 150))
                else
                    add("state", "Driver", "Empty", Color(180, 180, 180))
                end
            end
            if ent.GetPassengerSeats and isfunction(ent.GetPassengerSeats) then
                local ok, seats = pcall(ent.GetPassengerSeats, ent)
                if ok and istable(seats) then
                    local totalSeats = #seats
                    local occupied = 0
                    for _, s in pairs(seats) do
                        if IsValid(s) and IsValid(s:GetDriver()) then occupied = occupied + 1 end
                    end
                    add("state", "Passenger Seats", occupied .. " / " .. totalSeats .. " occupied", Color(180, 220, 255))
                end
            end
        end
    end

    if isNPC then
        add("state", "NPC State", PB.firstValue(saved, "npcState", "AIState"))
        add("state", "Hull", PB.firstValue(saved, "hullType", "HullType"))
        add("state", "SchedID", saved.schedule and saved.schedule.id)
        add("state", "Cycle", saved.cycle and string.format("%.2f", saved.cycle))
        add("state", "Seq", saved.sequence)
        add("state", "Playback", saved.playbackRate)
    else
        add("state", "Frozen", RARELOAD.TextUtils.BoolToYesNo(saved.frozen))
    end

    if isNPC then
        if saved.squad or saved.Squad then add("behavior", "Squad", PB.firstValue(saved, "squad", "Squad")) end
        add("behavior", "Leader", RARELOAD.TextUtils.BoolToYesNo(saved.squadLeader))
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
            add("meta", RARELOAD.TextUtils.HumanizeKeyLabel(tostring(key)), summary)
            metaAdded = metaAdded + 1
        end
    end

    if #metaKeys > metaAdded then
        add("meta", "+more", ("%d more..."):format(#metaKeys - metaAdded), Color(150, 150, 150))
    end
end
