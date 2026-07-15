SED                     = SED or (RARELOAD and RARELOAD.SavedEntityDisplay) or {}
SED.Phantom             = SED.Phantom or {}
SED.TrackedPhantoms     = SED.TrackedPhantoms or {}
SED.PhantomSavedRecords = SED.PhantomSavedRecords or {}
SED.PlayerPhantoms      = SED.PlayerPhantoms or {}

local Phantom           = SED.Phantom
if Phantom._initialized then return Phantom end

local RS = SED.Require("RenderShared", "rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_phantom.lua\n")
    return Phantom
end

local SS = SED.Require("Shared", "rareload/client/saved_entity_display/SED_shared.lua")
if not (SS and SS._initialized) then
    ErrorNoHalt("[Rareload] Missing SED.Shared in SED_phantom.lua\n")
    return Phantom
end

local PB = SED and SED.PanelBuilder
if not PB then
    include("rareload/client/saved_entity_display/SED_panel_builder_utils.lua")
    PB = SED and SED.PanelBuilder
end

local SnapshotUtils           = include("rareload/shared/rareload_snapshot_utils.lua")

local function L(key, ...)
    if RARELOAD and RARELOAD.L then return RARELOAD.L(key, ...) end
    return key
end

local moveTypeNames           = {
    [0] = "MOVETYPE_NONE",
    [1] = "MOVETYPE_ISOMETRIC",
    [2] = "MOVETYPE_WALK",
    [3] = "MOVETYPE_STEP",
    [4] = "MOVETYPE_FLY",
    [5] = "MOVETYPE_FLYGRAVITY",
    [6] = "MOVETYPE_VPHYSICS",
    [7] = "MOVETYPE_PUSH",
    [8] = "MOVETYPE_NOCLIP",
    [9] = "MOVETYPE_LADDER",
    [10] = "MOVETYPE_OBSERVER",
    [11] = "MOVETYPE_CUSTOM"
}

-- second element is a localization key, resolved via RARELOAD.L at draw time
local PHANTOM_CATEGORIES      = {
    { "basic",     "sed.cat.basic",     Color(70, 130, 180) },
    { "position",  "sed.cat.position",  Color(60, 179, 113) },
    { "equipment", "sed.cat.equipment", Color(218, 165, 32) },
    { "entities",  "sed.cat.entities",  Color(178, 34, 34) },
    { "stats",     "sed.cat.stats",     Color(147, 112, 219) }
}

local CACHE_LIFETIME = 5

function Phantom.BuildPhantomInfoData(ply, savedInfo, mapName, lodLevel)
    lodLevel      = lodLevel or 1
    local data    = { basic = {}, position = {}, equipment = {}, entities = {}, stats = {} }

    local name    = IsValid(ply) and ply:Nick() or L("common.unknown")
    local steamID = IsValid(ply) and ply:SteamID() or L("common.unknown")

    PB.addLine(data.basic, L("sed.phantom.player"), name, Color(255, 255, 255))
    PB.addLine(data.basic, L("sed.phantom.steamid"), steamID, Color(200, 200, 200))
    PB.addLine(data.basic, L("sed.phantom.map"), mapName or game.GetMap(), Color(180, 180, 200))

    if not savedInfo then
        PB.addLine(data.basic, L("sed.phantom.status"), L("sed.phantom.no_saved_data"), Color(255, 100, 100))
        return data
    end

    if savedInfo.playermodel then
        PB.addLine(data.basic, L("sed.phantom.model"), savedInfo.playermodel, Color(200, 200, 200))
    end

    if lodLevel <= 2 then
        local savedItems = {}
        if savedInfo.health then savedItems[#savedItems + 1] = L("sed.phantom.item.health") end
        if savedInfo.armor then savedItems[#savedItems + 1] = L("sed.phantom.item.armor") end
        if savedInfo.inventory and #savedInfo.inventory > 0 then savedItems[#savedItems + 1] = L("sed.phantom.item.inventory") end
        if savedInfo.ammo then savedItems[#savedItems + 1] = L("sed.phantom.item.ammo") end
        if savedInfo.playerStates then savedItems[#savedItems + 1] = L("sed.phantom.item.states") end
        if savedInfo.vehicles and #savedInfo.vehicles > 0 then savedItems[#savedItems + 1] = L("sed.phantom.item.vehicles") end
        if savedInfo.vehicleState then savedItems[#savedItems + 1] = L("sed.phantom.item.vehicle_state") end

        local entS = SnapshotUtils.GetSummary(savedInfo.entities, { category = "entity" }) or {}
        local npcS = SnapshotUtils.GetSummary(savedInfo.npcs, { category = "npc" }) or {}
        if PB.countEntries(entS) > 0 then savedItems[#savedItems + 1] = L("sed.phantom.item.entities") end
        if PB.countEntries(npcS) > 0 then savedItems[#savedItems + 1] = L("sed.phantom.item.npcs") end

        if #savedItems > 0 then
            PB.addLine(data.basic, L("sed.phantom.saved_data"), table.concat(savedItems, ", "), Color(150, 255, 150))
        end
    end

    if savedInfo.pos then
        local fmt = lodLevel <= 2
            and string.format("%.1f, %.1f, %.1f", savedInfo.pos.x, savedInfo.pos.y, savedInfo.pos.z)
            or string.format("(%d, %d, %d)",
                math.floor(savedInfo.pos.x), math.floor(savedInfo.pos.y), math.floor(savedInfo.pos.z))
        PB.addLine(data.position, L("sed.phantom.position"), fmt, Color(255, 255, 255))
    end

    if savedInfo.ang then
        PB.addLine(data.position, L("sed.phantom.direction"),
            string.format("%.1f, %.1f, %.1f", savedInfo.ang.p, savedInfo.ang.y, savedInfo.ang.r),
            Color(220, 220, 220))
    end

    if lodLevel <= 1 then
        PB.addLine(data.position, L("sed.phantom.move_type"),
            moveTypeNames[savedInfo.moveType] or L("common.unknown"), Color(220, 220, 220))
    end

    if savedInfo.activeWeapon then
        PB.addLine(data.equipment, L("sed.phantom.active_weapon"),
            PB.prettyClassName(savedInfo.activeWeapon), Color(255, 200, 200))
    end

    local function formatWeaponAmmo(ammoData)
        if type(ammoData) ~= "table" then return L("sed.phantom.no_ammo_saved") end
        local parts = {}
        local clip1 = math.floor(tonumber(ammoData.clip1) or -1)
        local res1  = math.floor(tonumber(ammoData.primary) or 0)
        local clip2 = math.floor(tonumber(ammoData.clip2) or -1)
        local res2  = math.floor(tonumber(ammoData.secondary) or 0)
        if clip1 >= 0 then parts[#parts + 1] = "C1 " .. clip1 end
        if res1 > 0 then parts[#parts + 1] = "R1 " .. res1 end
        if clip2 >= 0 then parts[#parts + 1] = "C2 " .. clip2 end
        if res2 > 0 then parts[#parts + 1] = "R2 " .. res2 end
        return #parts > 0 and table.concat(parts, " | ") or L("sed.phantom.no_ammo_saved")
    end

    local inventory    = type(savedInfo.inventory) == "table" and savedInfo.inventory or {}
    local ammoByWeapon = type(savedInfo.ammo) == "table" and savedInfo.ammo or nil

    if #inventory > 0 or ammoByWeapon then
        local invCounts, inInventory, weaponOrder = {}, {}, {}
        for _, class in ipairs(inventory) do
            class = tostring(class or "")
            if class ~= "" then
                invCounts[class] = (invCounts[class] or 0) + 1
                if not inInventory[class] then
                    inInventory[class] = true
                    weaponOrder[#weaponOrder + 1] = class
                end
            end
        end
        if ammoByWeapon then
            local ammoOnly = {}
            for class in pairs(ammoByWeapon) do
                class = tostring(class or "")
                if class ~= "" and not inInventory[class] then ammoOnly[#ammoOnly + 1] = class end
            end
            table.sort(ammoOnly)
            for _, c in ipairs(ammoOnly) do weaponOrder[#weaponOrder + 1] = c end
        end

        PB.addLine(data.equipment, L("sed.phantom.loadout"),
            L("sed.phantom.loadout_fmt", #inventory, #weaponOrder), Color(255, 220, 150))

        for _, class in ipairs(weaponOrder) do
            local count      = invCounts[class] or 0
            local isActive   = savedInfo.activeWeapon and class == savedInfo.activeWeapon
            local isAmmoOnly = not inInventory[class]
            local label      = (isActive and ">> " or " - ") .. PB.prettyClassName(class)
            if count > 1 then label = label .. " x" .. count end
            if isAmmoOnly then label = label .. L("sed.phantom.ammo_only_suffix") end
            local rowColor = isActive and Color(255, 230, 140)
                or (isAmmoOnly and Color(170, 220, 255) or Color(255, 210, 150))
            PB.addLine(data.equipment, label,
                formatWeaponAmmo(ammoByWeapon and ammoByWeapon[class]), rowColor, { noColon = true })
        end
    end

    local function processGroupedDataLOD(group, config)
        if type(group) ~= "table" or #group == 0 then
            PB.addLine(data.entities, config.totalLabel, "0", config.totalColor)
            return
        end
        PB.addLine(data.entities, config.totalLabel, tostring(#group), config.totalColor)
        if lodLevel > 2 then return end

        local counts       = {}
        local processCount = math.min(#group, lodLevel == 1 and 50 or 20)
        for i = 1, processCount do
            local entry = group[i]
            local class = (istable(entry) and (entry.class or entry.Class or entry[1])) or entry
            class = tostring(class or "unknown")
            counts[class] = (counts[class] or 0) + 1
        end

        local sorted = {}
        for class, count in pairs(counts) do sorted[#sorted + 1] = { class = class, count = count } end
        table.sort(sorted, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.class < b.class
        end)

        local showCount = math.min(#sorted, lodLevel == 1 and 10 or 5)
        for i = 1, showCount do
            PB.addLine(data.entities, config.labelPrefix .. " " .. i,
                string.format("%s (%d)", PB.prettyClassName(sorted[i].class), sorted[i].count),
                config.entryColor)
        end
        if #sorted > showCount then
            PB.addLine(data.entities, "...", L("sed.phantom.more_types", #sorted - showCount),
                Color(150, 150, 150))
        end
    end

    processGroupedDataLOD(
        SnapshotUtils.GetSummary(savedInfo.entities, { category = "entity" }) or {},
        {
            totalLabel = L("sed.phantom.total_entities"),
            totalColor = Color(255, 180, 180),
            labelPrefix = L("sed.phantom.entity_prefix"),
            entryColor = Color(255, 180, 180)
        })

    processGroupedDataLOD(
        SnapshotUtils.GetSummary(savedInfo.npcs, { category = "npc" }) or {},
        {
            totalLabel = L("sed.phantom.total_npcs"),
            totalColor = Color(200, 255, 200),
            labelPrefix = L("sed.phantom.npc_prefix"),
            entryColor = Color(200, 255, 200)
        })

    PB.addLine(data.stats, L("sed.phantom.item.health"), math.floor(savedInfo.health or 0), Color(255, 180, 180))
    PB.addLine(data.stats, L("sed.phantom.item.armor"), math.floor(savedInfo.armor or 0), Color(180, 180, 255))

    if savedInfo.playerStates and type(savedInfo.playerStates) == "table" then
        local states = {}
        if savedInfo.playerStates.godmode then states[#states + 1] = "God" end
        if savedInfo.playerStates.notarget then states[#states + 1] = "NoTarget" end
        if savedInfo.playerStates.frozen then states[#states + 1] = "Frozen" end
        if savedInfo.playerStates.noclip then states[#states + 1] = "Noclip" end
        if #states > 0 then
            PB.addLine(data.stats, L("sed.phantom.player_states"), table.concat(states, ", "), Color(255, 215, 0))
        end
    end

    if savedInfo.ammo and type(savedInfo.ammo) == "table" then
        local totalAmmo, ammoWeapons = 0, 0
        for _, ammoData in pairs(savedInfo.ammo) do
            local wt = (ammoData.primary and ammoData.primary > 0 and ammoData.primary or 0)
                + (ammoData.secondary and ammoData.secondary > 0 and ammoData.secondary or 0)
                + (ammoData.clip1 and ammoData.clip1 > 0 and ammoData.clip1 or 0)
                + (ammoData.clip2 and ammoData.clip2 > 0 and ammoData.clip2 or 0)
            if wt > 0 then
                ammoWeapons = ammoWeapons + 1; totalAmmo = totalAmmo + wt
            end
        end
        if totalAmmo > 0 then
            PB.addLine(data.stats, L("sed.phantom.ammo_reserve"),
                L("sed.phantom.ammo_reserve_fmt", totalAmmo, ammoWeapons), Color(255, 200, 100))
        end
    end

    if savedInfo.vehicles and type(savedInfo.vehicles) == "table" and #savedInfo.vehicles > 0 then
        PB.addLine(data.stats, L("sed.phantom.saved_vehicles"), #savedInfo.vehicles, Color(200, 200, 255))
    end
    if savedInfo.vehicleState and type(savedInfo.vehicleState) == "table" then
        PB.addLine(data.stats, L("sed.phantom.in_vehicle"),
            savedInfo.vehicleState.class or L("common.unknown"), Color(200, 200, 255))
    end

    return data
end

function Phantom.BuildSavedRecord(steamID, phantomData, mapName)
    local now    = CurTime()
    local cached = SED.PhantomSavedRecords[steamID]
    if cached and cached._expires > now then return cached end

    local ply                        = phantomData.ply
    local savedInfo                  = SED.GetPhantomSavedInfo(mapName, steamID)
    local name                       = IsValid(ply) and ply:Nick() or L("sed.phantom.player_fallback", steamID)

    local infoTarget                 = IsValid(ply) and ply or {
        Nick    = function() return name end,
        SteamID = function() return steamID end,
    }
    local infoData                   = Phantom.BuildPhantomInfoData(infoTarget, savedInfo, mapName, 1)

    local rec                        = {
        id                 = "phantom_" .. steamID,
        class              = name,
        _phantomTitle      = L("sed.phantom_title", name),
        _isPhantom         = true,
        _ownerSteamID      = steamID,
        MaxHealth          = savedInfo and savedInfo.health or 100,
        CurHealth          = savedInfo and savedInfo.health or 100,
        pos                = savedInfo and savedInfo.pos,
        ang                = savedInfo and savedInfo.ang,
        _phantomData       = infoData,
        _phantomCategories = PHANTOM_CATEGORIES,
        _expires           = now + CACHE_LIFETIME,
    }

    SED.PhantomSavedRecords[steamID] = rec
    return rec
end

local PLAYER_PHANTOM_CULL_SQR = 10000 * 10000
local PLAYER_MOVED_AWAY_SQR   = 32 * 32

local function EnsurePlayerPhantom(steamID, savedInfo)
    local existing = SED.PlayerPhantoms[steamID]
    if existing and IsValid(existing.phantom) then return existing end

    local pos = SS.ToVector(savedInfo.pos)
    if not pos then return nil end

    local model = savedInfo.playermodel
    if not model or model == "" then
        local owner = player.GetBySteamID(steamID)
        model = IsValid(owner) and owner:GetModel() or "models/player/kleiner.mdl"
    end

    local ang = SS.ToAngle(savedInfo.ang)
    local phantom = SS.MakePhantomModel(model, pos, Angle(0, ang.y, 0))
    if not phantom then return nil end

    local data = { phantom = phantom, steamID = steamID, pos = pos, ang = ang, model = model }
    SED.PlayerPhantoms[steamID] = data
    return data
end

function Phantom.RefreshModels()
    local mapName = game.GetMap()
    local byMap = RARELOAD.playerPositions and RARELOAD.playerPositions[mapName]
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local origin = lp:GetPos()

    if byMap then
        for steamID, savedInfo in pairs(byMap) do
            if istable(savedInfo) then
                local pos = SS.ToVector(savedInfo.pos)
                if pos and origin:DistToSqr(pos) <= PLAYER_PHANTOM_CULL_SQR then
                    EnsurePlayerPhantom(steamID, savedInfo)
                end
            end
        end
    end

    for steamID, data in pairs(SED.PlayerPhantoms) do
        local savedInfo = byMap and byMap[steamID]
        local keep = savedInfo and IsValid(data.phantom) and data.pos and
            origin:DistToSqr(data.pos) <= PLAYER_PHANTOM_CULL_SQR
        if not keep then
            if IsValid(data.phantom) then data.phantom:Remove() end
            SED.PlayerPhantoms[steamID] = nil
            SED.PhantomSavedRecords[steamID] = nil
        end
    end
end

function Phantom.UpdateModelVisibility()
    local reveal = SS.DebugEnabled() and SS.HasViewPhantomPerm()
    for steamID, data in pairs(SED.PlayerPhantoms) do
        if IsValid(data.phantom) then
            local show = false
            if reveal then
                local owner = player.GetBySteamID(steamID)
                if not IsValid(owner) then
                    show = true
                elseif owner:GetPos():DistToSqr(data.pos) > PLAYER_MOVED_AWAY_SQR then
                    show = true
                end
            end
            SS.SetPhantomRevealed(data.phantom, show)
        end
    end
end

function Phantom.RemoveAllModels()
    for steamID, data in pairs(SED.PlayerPhantoms) do
        if IsValid(data.phantom) then data.phantom:Remove() end
        SED.PlayerPhantoms[steamID] = nil
    end
    table.Empty(SED.TrackedPhantoms)
end

function Phantom.InjectTracked(mapName)
    if not SS.HasViewPhantomPerm() then
        Phantom.RemoveAllModels()
        if SED.PhantomSavedRecords then table.Empty(SED.PhantomSavedRecords) end
        return
    end

    mapName = mapName or game.GetMap()

    for ent, steamID in pairs(SED.TrackedPhantoms) do
        if not IsValid(ent) then
            SED.TrackedPhantoms[ent]         = nil
            SED.PhantomSavedRecords[steamID] = nil
        end
    end

    for steamID, data in pairs(SED.PlayerPhantoms) do
        if IsValid(data.phantom) then
            local owner = player.GetBySteamID(steamID)
            SED.PhantomSavedRecords[steamID] = Phantom.BuildSavedRecord(steamID, { ply = owner }, mapName)
            SED.TrackedPhantoms[data.phantom] = steamID
        end
    end
end

local nextModelRefresh, nextModelVis = 0, 0

hook.Add("Think", "RARELOAD_PlayerPhantom_Tick", function()
    if not SS.DebugEnabled() then
        if next(SED.PlayerPhantoms) then Phantom.RemoveAllModels() end
        return
    end

    local now = CurTime()
    if now >= nextModelRefresh then
        Phantom.RefreshModels()
        nextModelRefresh = now + 1.0
    end
    if now >= nextModelVis then
        Phantom.UpdateModelVisibility()
        nextModelVis = now + 0.5
    end
end)

hook.Add("RareloadPlayerPositionsUpdated", "RARELOAD_PlayerPhantom_Reset", function(mapName)
    if mapName ~= game.GetMap() then return end
    Phantom.RemoveAllModels()
    if SED.PhantomSavedRecords then table.Empty(SED.PhantomSavedRecords) end
    nextModelRefresh = 0
end)

hook.Add("PlayerDisconnected", "RARELOAD_PlayerPhantom_Cleanup", function(ply)
    if not IsValid(ply) then return end
    local steamID = ply:SteamID()
    local data = SED.PlayerPhantoms[steamID]
    if data then
        if IsValid(data.phantom) then data.phantom:Remove() end
        SED.PlayerPhantoms[steamID] = nil
    end
    for ent, sid in pairs(SED.TrackedPhantoms) do
        if sid == steamID then SED.TrackedPhantoms[ent] = nil end
    end
    SED.PhantomSavedRecords[steamID] = nil
end)

Phantom._initialized = true

return Phantom
