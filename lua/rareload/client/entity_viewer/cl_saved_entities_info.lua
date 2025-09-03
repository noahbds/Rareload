RARELOAD = RARELOAD or {}
RARELOAD._EntityInfo = RARELOAD._EntityInfo or {}
RARELOAD._NPCInfo = RARELOAD._NPCInfo or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}

local SAVED_ENTITIES_BY_ID = {}
local SAVED_NPCS_BY_ID = {}
local TrackedEntities = {}
local TrackedNPCs = {}
local MAP_LAST_BUILD = 0
local SAVED_LOOKUP_INTERVAL = 5
local LAST_RESCAN = 0
local RESCAN_INTERVAL = 2
local INFO_CACHE_LIFETIME = 0.5
local MAX_DRAW_PER_FRAME = 40
local DRAW_DISTANCE_SQR = 600 * 100
local BASE_SCALE = 0.11
local MAX_VISIBLE_LINES = 30
local SCROLL_SPEED = 3
local PanelScroll = { entities = {}, npcs = {} }
local InteractionState = { active = false, ent = nil, id = nil, isNPC = false, lastAction = 0 }
local KeyStates = {}
local KEY_REPEAT_DELAY = 0.25
local CandidateEnt, CandidateIsNPC, CandidateID, CandidateYawDiff
local INTERACT_KEY = KEY_E
local REQUIRE_SHIFT_MOD = true
local ScrollDelta = 0
local LeaveTime = 0

local lpCache

local function InteractModifierDown()
    if not REQUIRE_SHIFT_MOD then return true end
    if input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) then return true end
    local ply = lpCache
    if (not IsValid(ply)) then ply = LocalPlayer() end
    if IsValid(ply) and (ply:KeyDown(IN_SPEED) or ply:KeyDown(IN_WALK)) then return true end
    return false
end

local function KeyPressed(code)
    if not input.IsKeyDown(code) then return false end
    local t = CurTime()
    local last = KeyStates[code] or 0
    if t - last > KEY_REPEAT_DELAY then
        KeyStates[code] = t
        return true
    end
    return false
end

local function PlayerIsHoldingSomething()
    lpCache = lpCache or LocalPlayer()
    if not IsValid(lpCache) then return false end
    if lpCache:KeyDown(IN_USE) then
        local tr = lpCache:GetEyeTrace()
        if tr and IsValid(tr.Entity) and tr.Entity.IsPlayerHolding and tr.Entity:IsPlayerHolding() then
            return true
        end
    end
    local scanCount = 0
    for ent, _ in pairs(TrackedEntities) do
        if IsValid(ent) and ent.IsPlayerHolding and ent:IsPlayerHolding() then return true end
        scanCount = scanCount + 1
        if scanCount > 50 then break end
    end
    for ent, _ in pairs(TrackedNPCs) do
        if IsValid(ent) and ent.IsPlayerHolding and ent:IsPlayerHolding() then return true end
        scanCount = scanCount + 1
        if scanCount > 80 then break end
    end
    return false
end

local function EnterInteraction(ent, isNPC, id)
    InteractionState.active = true
    InteractionState.ent = ent
    InteractionState.id = id
    InteractionState.isNPC = isNPC
    InteractionState.lastAction = CurTime()
    lpCache = lpCache or LocalPlayer()
    if IsValid(lpCache) then
        InteractionState.lockAng = lpCache:EyeAngles()
        lpCache:DrawViewModel(false)
    end
end

local function LeaveInteraction()
    InteractionState.active = false
    InteractionState.ent = nil
    InteractionState.id = nil
    InteractionState.isNPC = false
    InteractionState.lockAng = nil
    LeaveTime = CurTime()
    if IsValid(lpCache) then
        lpCache:DrawViewModel(true)
    end
end

local lastPlayerCheck = 0

local THEME = _G.THEME or {
    background = Color(20, 20, 30, 220),
    header = Color(30, 30, 45, 255),
    border = Color(70, 130, 180, 255),
    text = Color(220, 220, 255)
}

local function ToVec(tbl)
    if not tbl then return Vector(0, 0, 0) end
    if isvector(tbl) then return tbl end
    if tbl.x then return Vector(tbl.x, tbl.y, tbl.z) end
    if istable(tbl) and #tbl == 3 then return Vector(tbl[1], tbl[2], tbl[3]) end
    return Vector(0, 0, 0)
end

local function RebuildSavedLookup()
    local map = game.GetMap()
    if not (RARELOAD.playerPositions and map) then return end
    SAVED_ENTITIES_BY_ID = {}
    SAVED_NPCS_BY_ID = {}

    for ownerSteamID, pdata in pairs(RARELOAD.playerPositions[map] or {}) do
        if istable(pdata) then
            if istable(pdata.entities) then
                for _, saved in ipairs(pdata.entities) do
                    if istable(saved) and saved.id then
                        saved._ownerSteamID = ownerSteamID
                        SAVED_ENTITIES_BY_ID[saved.id] = saved
                    end
                end
            end
            if istable(pdata.npcs) then
                for _, saved in ipairs(pdata.npcs) do
                    if istable(saved) and saved.id then
                        saved._ownerSteamID = ownerSteamID
                        SAVED_NPCS_BY_ID[saved.id] = saved
                    end
                end
            end
        end
    end
    MAP_LAST_BUILD = CurTime()
end

local function EnsureSavedLookup()
    if CurTime() - MAP_LAST_BUILD > SAVED_LOOKUP_INTERVAL then
        RebuildSavedLookup()
    end
end

local function TrackIfSaved(ent)
    if not IsValid(ent) or ent:IsPlayer() then return end
    local id = ent.GetNWString and ent:GetNWString("RareloadID", "") or ""
    if id == "" then return end
    EnsureSavedLookup()
    if ent:IsNPC() then
        if SAVED_NPCS_BY_ID[id] then
            TrackedNPCs[ent] = id
        end
    else
        if SAVED_ENTITIES_BY_ID[id] then
            TrackedEntities[ent] = id
        end
    end
end

hook.Add("OnEntityCreated", "RARELOAD_TrackSavedEntities", function(ent)
    timer.Simple(0, function()
        if IsValid(ent) then TrackIfSaved(ent) end
    end)
    timer.Simple(0.25, function()
        if IsValid(ent) and (not TrackedEntities[ent]) and (not TrackedNPCs[ent]) then TrackIfSaved(ent) end
    end)
end)

hook.Add("CreateMove", "RARELOAD_SavedPanels_CamLock", function(cmd)
    if InteractionState.active or CurTime() - LeaveTime < 0.5 then
        cmd:RemoveKey(IN_USE)
    end
    if not InteractionState.active then return end
    local ent = InteractionState.ent
    if not IsValid(ent) then return end
    lpCache = lpCache or LocalPlayer()
    if not IsValid(lpCache) then return end
    local ang = InteractionState.lockAng
    if not ang then
        ang = lpCache:EyeAngles()
        InteractionState.lockAng = ang
    end
    cmd:SetViewAngles(ang)
end)

hook.Add("EntityRemoved", "RARELOAD_UntrackSavedEntities", function(ent)
    if TrackedEntities[ent] then TrackedEntities[ent] = nil end
    if TrackedNPCs[ent] then TrackedNPCs[ent] = nil end
end)

hook.Add("PlayerBindPress", "RARELOAD_InteractScroll", function(ply, bind, pressed)
    if not InteractionState.active or not pressed then return end
    if bind == "invprev" then
        ScrollDelta = ScrollDelta - SCROLL_SPEED
        return true
    elseif bind == "invnext" then
        ScrollDelta = ScrollDelta + SCROLL_SPEED
        return true
    end
end)

local function RescanLate()
    if CurTime() - LAST_RESCAN < RESCAN_INTERVAL then return end
    LAST_RESCAN = CurTime()

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not TrackedEntities[ent] and not TrackedNPCs[ent] then
            TrackIfSaved(ent)
        end
    end
end

timer.Simple(1, function()
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then
            TrackIfSaved(ent)
        end
    end
end)

local ENT_CATEGORIES = {
    { "basic",     "Basic",      Color(64, 152, 255) },
    { "position",  "Position",   Color(60, 179, 113) },
    { "saved",     "Saved Data", Color(255, 140, 40) },
    { "state",     "State",      Color(218, 165, 32) },
    { "physics",   "Physics",    Color(255, 120, 90) },
    { "visual",    "Visual",     Color(147, 112, 219) },
    { "ownership", "Ownership",  Color(200, 150, 255) },
    { "keyvalues", "KeyValues",  Color(180, 180, 180) },
    { "meta",      "Meta",       Color(120, 200, 220) }
}
local NPC_CATEGORIES = {
    { "basic",     "Basic",      Color(64, 152, 255) },
    { "position",  "Position",   Color(60, 179, 113) },
    { "saved",     "Saved Data", Color(255, 140, 40) },
    { "state",     "State",      Color(218, 165, 32) },
    { "behavior",  "Behavior",   Color(214, 80, 80) },
    { "combat",    "Combat",     Color(255, 90, 140) },
    { "visual",    "Visual",     Color(147, 112, 219) },
    { "ownership", "Ownership",  Color(200, 150, 255) },
    { "relations", "Relations",  Color(120, 200, 220) },
    { "keyvalues", "KeyValues",  Color(180, 180, 180) },
    { "meta",      "Meta",       Color(120, 200, 220) }
}

local EntityPanelCache = {}
local NPCPanelCache = {}

local function BuildPanelData(saved, ent, isNPC)
    if not saved then return nil end
    local panelCache = isNPC and NPCPanelCache or EntityPanelCache
    local id = saved.id or (saved.class .. "#" .. tostring(saved.spawnTime or 0))
    local now = CurTime()
    local entry = panelCache[id]
    if entry and entry.expires > now then return entry end

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
        table.insert(cats[cat], { label, tostring(value), col or THEME.text, opts })
    end

    add("basic", isNPC and "NPC ID" or "Entity ID", saved.id)
    add("basic", "Class", saved.class)
    if saved.model then add("basic", "Model", (saved.model:match("([^/\\]+)$") or saved.model)) end
    if saved.owner or saved._ownerSteamID then add("basic", "Owner", saved.owner or saved._ownerSteamID) end
    if saved.spawnTime then add("basic", "Spawned", os.date("%H:%M:%S", saved.spawnTime)) end
    if saved.stateHash then add("basic", "StateHash", saved.stateHash) end
    if saved.flags and not isNPC then add("basic", "Flags", saved.flags) end

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
    if saved.physics then
        local phys = saved.physics
        if istable(phys) then
            if phys.exists ~= nil then add("saved", "Physics Exists", phys.exists and "Yes" or "No") end
            if phys.velocity then add("saved", "Physics Velocity", phys.velocity) end
            if phys.frozen ~= nil then add("saved", "Physics Frozen", phys.frozen and "Yes" or "No") end
            if phys.mass then add("saved", "Physics Mass", phys.mass) end
            if phys.material then add("saved", "Physics Material", phys.material) end
            if phys.gravityEnabled ~= nil then add("saved", "Gravity Enabled", phys.gravityEnabled and "Yes" or "No") end
            if phys.motionEnabled ~= nil then add("saved", "Motion Enabled", phys.motionEnabled and "Yes" or "No") end
        end
    end
    if isNPC then
        if saved.isControlled ~= nil then add("saved", "Was Controlled", saved.isControlled and "Yes" or "No") end
        if saved.expression then add("saved", "Expression", saved.expression) end
        if saved.cycle then add("saved", "Anim Cycle", string.format("%.3f", saved.cycle)) end
        if saved.sequence then add("saved", "Sequence", saved.sequence) end
        if saved.playbackRate then add("saved", "Playback Rate", string.format("%.2f", saved.playbackRate)) end
    end

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
    if IsValid(ent) then
        local v = ent:GetPos()
        local p = saved.pos
        local a = saved.ang
        add("position", "Live Pos", string.format("%.0f %.0f %.0f", v.x, v.y, v.z))
        add("position", "Live Ang",
            string.format("%.0f %.0f %.0f", ent:GetAngles().p, ent:GetAngles().y, ent:GetAngles().r))
        add("position", "Live Vel",
            string.format("%.0f %.0f %.0f", ent:GetVelocity().x, ent:GetVelocity().y, ent:GetVelocity().z))
    end

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

    if isNPC then
        if saved.squad then add("behavior", "Squad", saved.squad) end
        if saved.squadLeader ~= nil then add("behavior", "Leader", saved.squadLeader and "Yes" or "No") end
        if saved.target and saved.target.type then
            add("behavior", "Target", saved.target.type .. ":" .. (saved.target.id or saved.target.class or "?"))
        end
        if saved.weapons and #saved.weapons > 0 then add("combat", "Weapons", #saved.weapons) end
        if istable(saved.weapons) then
            for i, w in ipairs(saved.weapons) do
                if istable(w) then
                    add("combat", "W" .. i, w.class or w.name)
                end
            end
        end
        if saved.weaponProficiency then add("combat", "Proficiency", saved.weaponProficiency) end
        if saved.playerRelationship then add("relations", "PlayerRel", saved.playerRelationship) end
        if saved.relations and saved.relations.players then
            local count = table.Count(saved.relations.players)
            add("relations", "Player Rels", count)
            local shown = 0
            for steamid, rel in pairs(saved.relations.players) do
                if shown >= 4 then break end
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

    if istable(saved.bodygroups) then
        for k, v in pairs(saved.bodygroups) do
            add("visual", "BG " .. k, v)
        end
    end
    if istable(saved.subMaterials) then
        for idx, mat in pairs(saved.subMaterials) do
            add("visual", "SubMat" .. idx, mat ~= "" and (mat:match("([^/\\]+)$") or mat) or "<default>")
        end
    end

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
    if saved.spawnflags then add("ownership", "SpawnFlags", saved.spawnflags) end
    if saved.originallySpawnedBy then add("ownership", "SpawnedBy", saved.originallySpawnedBy) end
    if saved.ownerSteamID then add("ownership", "OwnerID", saved.ownerSteamID) end

    if istable(saved.keyvalues) or istable(saved.keyValues) then
        local kv = saved.keyvalues or saved.keyValues
        local added = 0
        for k, v in pairs(kv) do
            if added >= 16 then break end
            add("keyvalues", tostring(k), type(v) == "string" and v or tostring(v))
            added = added + 1
        end
    end

    local used = {}
    for cname, list in pairs(cats) do
        for _, line in ipairs(list) do
            used[line[1]] = true
        end
    end
    for k, v in pairs(saved) do
        if k ~= "_ownerSteamID" and k ~= "id" and not used[k] then
            local t = type(v)
            if t == "table" then
                local count = table.Count(v)
                if count == 0 then
                    add("meta", k, "{}")
                elseif count <= 5 then
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
        end
    end

    entry = {
        data = cats,
        expires = now + INFO_CACHE_LIFETIME,
        activeCat = (panelCache[id] and panelCache[id].activeCat) or "basic",
        widths = {}
    }
    panelCache[id] = entry
    return entry
end

local surface_SetFont = surface.SetFont
local surface_GetTextSize = surface.GetTextSize
local surface_SetDrawColor = surface.SetDrawColor
local draw_SimpleText = draw.SimpleText
local draw_RoundedBox = draw.RoundedBox

local function DrawSavedPanel(ent, saved, isNPC)
    if not (IsValid(ent) and saved) then return end
    lpCache = lpCache or LocalPlayer(); if not IsValid(lpCache) then return end
    local eyePos = lpCache:EyePos(); local pos = ent:GetPos(); local distSqr = eyePos:DistToSqr(pos)
    if distSqr > DRAW_DISTANCE_SQR then return end

    local cache = BuildPanelData(saved, ent, isNPC); if not cache then return end
    local categories = isNPC and NPC_CATEGORIES or ENT_CATEGORIES
    local activeCat = cache.activeCat
    local lines = cache.data[activeCat] or {}
    local lineHeight = 18; local titleHeight = 36; local tabHeight = 22

    local width = cache.widths[activeCat] or 360
    if not cache.widths[activeCat] then
        surface_SetFont("Trebuchet18")
        for i = 1, #lines do
            local l = lines[i]
            local w1 = surface_GetTextSize((l[1] or "") .. ":")
            local w2 = surface_GetTextSize(l[2] or "")
            width = math.max(width, w1 + w2 + 170)
            if width > 680 then break end
        end
        local minTabWidth = 60
        local minWidthForTabs = #categories * minTabWidth
        width = math.max(width, minWidthForTabs)
        width = math.Clamp(width, 340, 680)
        cache.widths[activeCat] = width
    end

    local panelID = saved.id or (saved.class .. "?")
    local scrollTable = isNPC and PanelScroll.npcs or PanelScroll.entities
    local scrollKey = panelID .. "_" .. activeCat
    local maxScrollLines = math.max(0, #lines - MAX_VISIBLE_LINES)
    local currentScroll = math.min(scrollTable[scrollKey] or 0, maxScrollLines)
    scrollTable[scrollKey] = currentScroll

    local visibleLines = math.min(#lines - currentScroll, MAX_VISIBLE_LINES)
    local contentHeight = visibleLines * lineHeight + 12
    local panelHeight = titleHeight + tabHeight + contentHeight + 18

    local dir = (pos - eyePos); dir:Normalize(); local ang = dir:Angle(); ang.y = ang.y - 90; ang.p = 0; ang.r = 90
    local scale = BASE_SCALE * math.Clamp(1 - (math.sqrt(distSqr) / 4000), 0.4, 1.2)

    local obbMin, obbMax = Vector(0, 0, 0), Vector(0, 0, 0)
    if ent.OBBMins and ent.OBBMaxs then
        local okMin, bmin = pcall(ent.OBBMins, ent)
        local okMax, bmax = pcall(ent.OBBMaxs, ent)
        if okMin and okMax and bmin and bmax then
            obbMin, obbMax = bmin, bmax
        end
    end

    local entityHeight = math.max(30, obbMax.z - obbMin.z)
    local buffer = math.max(15, entityHeight * 0.1)

    local frameHeightWorldUnits = panelHeight * scale

    local frameBottomZ = pos.z + obbMax.z + buffer
    local frameCenterZ = frameBottomZ + (frameHeightWorldUnits / 2)

    local drawPos = Vector(pos.x, pos.y, frameCenterZ)
    local offsetX = -width / 2; local offsetY = -panelHeight / 2

    cam.Start3D2D(drawPos, ang, scale)
    surface_SetDrawColor(0, 0, 0, 130)
    surface.DrawRect(offsetX + 4, offsetY + 4, width, panelHeight)
    draw_RoundedBox(10, offsetX, offsetY, width, panelHeight, Color(15, 18, 26, 240))
    draw_RoundedBox(10, offsetX + 2, offsetY + 2, width - 4, panelHeight - 4, Color(26, 30, 40, 245))
    for i = 0, 1 do
        surface_SetDrawColor(THEME.border.r, THEME.border.g, THEME.border.b, 170 - i * 90)
        surface.DrawOutlinedRect(offsetX + i, offsetY + i, width - i * 2, panelHeight - i * 2, 1)
    end
    surface_SetDrawColor(THEME.header.r, THEME.header.g, THEME.header.b, 245)
    surface.DrawRect(offsetX, offsetY, width, titleHeight)
    local title = isNPC and "Saved NPC" or "Saved Entity"
    draw_SimpleText(title, "Trebuchet24", offsetX + 12, offsetY + titleHeight / 2, Color(240, 240, 255), TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
    local maxHP = saved.maxHealth or 0
    local curHP = saved.health or 0
    if maxHP > 0 then
        local barW = 180
        local hpFrac = math.Clamp(curHP / maxHP, 0, 1)
        local bx = offsetX + width - barW - 16
        local by = offsetY + 8
        draw_RoundedBox(4, bx, by, barW, 14, Color(35, 40, 52, 190))
        draw_RoundedBox(4, bx + 1, by + 1, (barW - 2) * hpFrac, 12,
            Color(120 + 100 * (1 - hpFrac), 220 * hpFrac, 90, 230))
        draw_SimpleText(curHP .. "/" .. maxHP, "Trebuchet18", bx + barW / 2, by + 7, Color(230, 230, 240),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local tabY = offsetY + titleHeight
    local tabWidth = width / #categories
    for i, cat in ipairs(categories) do
        local catId, name, col = cat[1], cat[2], cat[3]
        local tabX = offsetX + (i - 1) * tabWidth
        local active = (catId == activeCat)
        surface_SetDrawColor(col.r * (active and 0.6 or 0.25), col.g * (active and 0.6 or 0.25),
            col.b * (active and 0.6 or 0.25), active and 230 or 130)
        surface.DrawRect(tabX, tabY, tabWidth, tabHeight)
        if active then
            surface_SetDrawColor(col.r, col.g, col.b, 255)
            surface.DrawOutlinedRect(tabX, tabY, tabWidth, tabHeight, 1)
        end
        draw_SimpleText(name, "Trebuchet18", tabX + tabWidth / 2, tabY + tabHeight / 2,
            active and Color(255, 255, 255) or Color(205, 205, 205), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local startY = tabY + tabHeight + 6
    surface_SetFont("Trebuchet18")
    for i = 1, visibleLines do
        local l = lines[currentScroll + i]
        if not l then break end
        local y = startY + (i - 1) * lineHeight
        if (i + currentScroll) % 2 == 0 then
            surface_SetDrawColor(40, 48, 62, 95)
            surface.DrawRect(offsetX + 6, y - 2, width - 12, lineHeight)
        end
        draw_SimpleText(l[1] .. ":", "Trebuchet18", offsetX + 14, y, Color(210, 210, 215), TEXT_ALIGN_LEFT,
            TEXT_ALIGN_TOP)
        draw_SimpleText(l[2], "Trebuchet18", offsetX + 180, y, l[3] or THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    if maxScrollLines > 0 then
        local barW = 5
        local barX = offsetX + width - barW - 10
        local barY = startY - 2
        local barH = contentHeight - 4
        draw_RoundedBox(3, barX, barY, barW, barH, Color(30, 34, 44, 185))
        local handleH = math.max(16, barH * (visibleLines / #lines))
        local handleY = barY + (barH - handleH) * (currentScroll / maxScrollLines)
        draw_RoundedBox(3, barX, handleY, barW, handleH, Color(90, 150, 230, 220))
    end
    local aimAng = lpCache:EyeAngles()
    local toEntAng = (pos - lpCache:EyePos()):Angle()
    local yawDiff = math.abs(math.AngleDifference(aimAng.y, toEntAng.y))
    local isFocused = InteractionState.active and InteractionState.ent == ent
    local isCandidate = false
    if not InteractionState.active and distSqr < 40000 and yawDiff < 10 then
        isCandidate = true
        if not CandidateEnt or yawDiff < (CandidateYawDiff or 999) then
            CandidateEnt = ent; CandidateIsNPC = isNPC; CandidateID = panelID; CandidateYawDiff = yawDiff
        end
    end
    if isFocused then
        draw_SimpleText("INTERACT MODE", "Trebuchet18", offsetX + width / 2, offsetY - 6, Color(255, 235, 190),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
        draw_SimpleText("Left/Right Tabs | Up/Down/MWheel Scroll | Shift+E Exit", "Trebuchet18", offsetX + width / 2,
            offsetY + panelHeight + 4, Color(225, 225, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    elseif isCandidate then
        draw_SimpleText("Shift + E to Inspect", "Trebuchet18", offsetX + width / 2, offsetY - 6, Color(160, 210, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    end
    cam.End3D2D()
end

local function DrawAllSavedPanels()
    EnsureSavedLookup()
    RescanLate()

    lpCache = lpCache or LocalPlayer()
    if not IsValid(lpCache) then return end

    local eyePos = lpCache:EyePos()
    local drawList = {}
    local listCount = 0

    local invalidEntities = {}
    for ent, id in pairs(TrackedEntities) do
        if IsValid(ent) then
            local rec = SAVED_ENTITIES_BY_ID[id]
            if rec then
                local distSqr = eyePos:DistToSqr(ent:GetPos())
                if distSqr <= DRAW_DISTANCE_SQR then
                    listCount = listCount + 1
                    drawList[listCount] = {
                        ent = ent,
                        saved = rec,
                        isNPC = false,
                        distSqr = distSqr
                    }
                end
            end
        else
            invalidEntities[#invalidEntities + 1] = ent
        end
    end

    local invalidNPCs = {}
    for npc, id in pairs(TrackedNPCs) do
        if IsValid(npc) then
            local rec = SAVED_NPCS_BY_ID[id]
            if rec then
                local distSqr = eyePos:DistToSqr(npc:GetPos())
                if distSqr <= DRAW_DISTANCE_SQR then
                    listCount = listCount + 1
                    drawList[listCount] = {
                        ent = npc,
                        saved = rec,
                        isNPC = true,
                        distSqr = distSqr
                    }
                end
            end
        else
            invalidNPCs[#invalidNPCs + 1] = npc
        end
    end

    for i = 1, #invalidEntities do
        TrackedEntities[invalidEntities[i]] = nil
    end
    for i = 1, #invalidNPCs do
        TrackedNPCs[invalidNPCs[i]] = nil
    end

    if listCount == 0 then return end

    table.sort(drawList, function(a, b) return a.distSqr > b.distSqr end)

    local maxDraw = math.min(listCount, MAX_DRAW_PER_FRAME)
    for i = 1, maxDraw do
        local item = drawList[i]
        DrawSavedPanel(item.ent, item.saved, item.isNPC)
    end
end

function DrawEntitiesInfo()
end

function DrawNpcsInfo()
end

hook.Add("PostDrawOpaqueRenderables", "Rareload_DrawSavedEntitiesAndNPCs", function()
    if not (RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled) then
        if InteractionState.active then
            LeaveInteraction()
        end
        return
    end

    local currentTime = CurTime()

    if currentTime - lastPlayerCheck > 7.5 then
        lpCache = LocalPlayer()
        lastPlayerCheck = currentTime
    end
    if not IsValid(lpCache) then return end

    CandidateEnt, CandidateIsNPC, CandidateID, CandidateYawDiff = nil, nil, nil, nil

    DrawAllSavedPanels()

    if InteractionState.active then
        local ent = InteractionState.ent
        if not IsValid(ent) then
            LeaveInteraction()
            return
        end

        local eyePos = lpCache:EyePos()
        local entPos = ent:GetPos()
        local distSqr = eyePos:DistToSqr(entPos)

        if distSqr > DRAW_DISTANCE_SQR * 1.1 then
            LeaveInteraction()
            return
        end

        if KeyPressed(INTERACT_KEY) and InteractModifierDown() then
            LeaveInteraction()
            return
        end

        local isNPC = InteractionState.isNPC
        local interactionID = InteractionState.id

        if not interactionID then
            LeaveInteraction()
            return
        end

        local savedRec = isNPC and SAVED_NPCS_BY_ID[interactionID] or SAVED_ENTITIES_BY_ID[interactionID]
        if not savedRec then
            LeaveInteraction()
            return
        end

        local panelCache = isNPC and NPCPanelCache or EntityPanelCache
        local cache = panelCache[interactionID]
        if not cache then
            cache = BuildPanelData(savedRec, ent, isNPC)
        end

        if cache and cache.activeCat then
            local categoryList = isNPC and NPC_CATEGORIES or ENT_CATEGORIES
            local scrollTable = isNPC and PanelScroll.npcs or PanelScroll.entities

            if KeyPressed(KEY_RIGHT) or KeyPressed(KEY_LEFT) then
                local dir = (input.IsKeyDown(KEY_RIGHT) and not input.IsKeyDown(KEY_LEFT)) and 1 or -1
                local currentIdx = 1

                for i, cat in ipairs(categoryList) do
                    if cat[1] == cache.activeCat then
                        currentIdx = i
                        break
                    end
                end

                currentIdx = currentIdx + dir
                if currentIdx < 1 then
                    currentIdx = #categoryList
                elseif currentIdx > #categoryList then
                    currentIdx = 1
                end

                cache.activeCat = categoryList[currentIdx][1]
                scrollTable[interactionID .. "_" .. cache.activeCat] = 0
            end

            local scrollDelta = ScrollDelta
            if input.IsKeyDown(KEY_UP) then scrollDelta = scrollDelta - SCROLL_SPEED end
            if input.IsKeyDown(KEY_DOWN) then scrollDelta = scrollDelta + SCROLL_SPEED end

            if scrollDelta ~= 0 then
                local scrollKey = interactionID .. "_" .. cache.activeCat
                local lines = cache.data[cache.activeCat] or {}
                local maxScrollLines = math.max(0, #lines - MAX_VISIBLE_LINES)

                if maxScrollLines > 0 then
                    local currentScroll = math.min(scrollTable[scrollKey] or 0, maxScrollLines)
                    scrollTable[scrollKey] = math.Clamp(currentScroll + scrollDelta, 0, maxScrollLines)
                end
                ScrollDelta = 0
            end
        end
    else
        if CandidateEnt and KeyPressed(INTERACT_KEY) and InteractModifierDown() and not PlayerIsHoldingSomething() then
            EnterInteraction(CandidateEnt, CandidateIsNPC, CandidateID)
        end
    end
end)
