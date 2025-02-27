RARELOAD = RARELOAD or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.Phantom = RARELOAD.Phantom or {}

local function createPhantom(ply, pos, ang)
    if not IsValid(ply) then return end

    local phantom = ents.CreateClientProp(ply:GetModel())
    if not IsValid(phantom) then return end

    phantom:SetPos(pos)
    phantom:SetAngles(ang)
    phantom:SetRenderMode(RENDERMODE_TRANSALPHA)

    if RARELOAD.settings.debugEnabled then
        phantom:SetColor(Color(255, 255, 255, 150))
        phantom:SetNoDraw(false)
    else
        phantom:SetColor(Color(0, 0, 0, 0))
        phantom:SetNoDraw(true)
    end

    phantom:Spawn()
    phantom:SetMoveType(MOVETYPE_NONE)
    phantom:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    return phantom
end

local function updatePhantomVisibility()
    local isDebugEnabled = RARELOAD.settings.debugEnabled

    for steamID, phantomData in pairs(RARELOAD.Phantom) do
        local phantom = phantomData.phantom
        if IsValid(phantom) then
            if isDebugEnabled then
                phantom:SetColor(Color(255, 255, 255, 150))
                phantom:SetNoDraw(false)
            else
                phantom:SetColor(Color(0, 0, 0, 0))
                phantom:SetNoDraw(true)
            end
        end
    end
end

local function removePhantom(steamID)
    if not steamID then return end

    local existingPhantom = RARELOAD.Phantom[steamID] and RARELOAD.Phantom[steamID].phantom
    if IsValid(existingPhantom) then
        SafeRemoveEntity(existingPhantom)
    end
    RARELOAD.Phantom[steamID] = nil
end

local function handleNetReceive(event, callback)
    net.Receive(event, function(len, ply)
        if not IsValid(ply) then return end
        callback()
    end)
end

handleNetReceive("SyncData", function()
    local data = net.ReadTable()
    if not data or type(data) ~= "table" then return end

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = data.playerPositions or {}

    local oldDebugEnabled = RARELOAD.settings.debugEnabled
    RARELOAD.settings = data.settings or {}
    RARELOAD.Phantom = data.Phantom or {}

    if oldDebugEnabled ~= RARELOAD.settings.debugEnabled then
        updatePhantomVisibility()
    end
end)

handleNetReceive("CreatePlayerPhantom", function()
    local ply = net.ReadEntity()
    if not IsValid(ply) then
        print("[RARELOAD DEBUG] Invalid player entity received.")
        return
    end

    local pos, ang = net.ReadVector(), net.ReadAngle()
    if not pos or pos:IsZero() then
        print("[RARELOAD DEBUG] Invalid position for phantom creation.")
        return
    end

    ---@diagnostic disable-next-line: undefined-field
    local steamID = ply:SteamID()
    if not steamID then return end

    removePhantom(steamID)

    RARELOAD.Phantom[steamID] = {
        phantom = createPhantom(ply, pos, ang),
        ply = ply
    }
end)

handleNetReceive("RemovePlayerPhantom", function()
    local ply = net.ReadEntity()
    if IsValid(ply) then
        ---@diagnostic disable-next-line: undefined-field
        removePhantom(ply:SteamID())
    end
end)

local fileNotExistPrinted = false


local function reloadSavedData()
    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".json"

    if not file.Exists(filePath, "DATA") then
        if not fileNotExistPrinted then
            print("[RARELOAD DEBUG] File does not exist: " .. filePath)
            fileNotExistPrinted = true
        end
        return
    end

    local data = file.Read(filePath, "DATA")
    if not data or data == "" then
        print("[RARELOAD DEBUG] File is empty: " .. filePath)
        return
    end

    local status, result = pcall(util.JSONToTable, data)
    if status and result then
        RARELOAD.playerPositions = result
    else
        print("[RARELOAD DEBUG] Error parsing JSON: " .. tostring(result))
    end
end

local moveTypeNames = {
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
    [11] = "MOVETYPE_CUSTOM",
}

local phantomInfoCache = {}
local CACHE_LIFETIME = 2
local PHANTOM_CATEGORIES = {
    { "basic",     "Basic Information",     Color(70, 130, 180) },
    { "position",  "Position and Movement", Color(60, 179, 113) },
    { "equipment", "Equipment",             Color(218, 165, 32) },
    { "entities",  "Saved Entities",        Color(178, 34, 34) },
    { "stats",     "Statistics",            Color(147, 112, 219) }
}

function table.map(tbl, func)
    if not tbl or type(tbl) ~= "table" then return {} end
    local t = {}
    for k, v in pairs(tbl) do
        t[k] = func(v, k)
    end
    return t
end

local function VectorToString(vec)
    return string.format("%.1f, %.1f, %.1f", vec.x, vec.y, vec.z)
end

local function AngleToString(ang)
    return string.format("%.1f, %.1f, %.1f", ang.p, ang.y, ang.r)
end

local function formatEntityList(items, limit)
    local count = #items
    if count <= limit then
        return table.concat(items, ", ")
    else
        local shortened = {}
        for i = 1, limit do
            table.insert(shortened, items[i])
        end
        return table.concat(shortened, ", ") .. string.format(" (+%d autres)", count - limit)
    end
end

local function buildPhantomInfoData(ply, SavedInfo, mapName)
    local data = {
        basic = {},
        position = {},
        equipment = {},
        entities = {},
        stats = {}
    }

    if SavedInfo then
        table.insert(data.basic, { "Player", ply:Nick(), Color(255, 255, 255) })
        table.insert(data.basic, { "SteamID", ply:SteamID(), Color(200, 200, 200) })
        table.insert(data.basic, { "Model", ply:GetModel(), Color(200, 200, 200) })

        table.insert(data.position, { "Position", VectorToString(SavedInfo.pos), Color(255, 255, 255) })
        table.insert(data.position, { "Direction", AngleToString(SavedInfo.ang), Color(220, 220, 220) })
        table.insert(data.position,
            { "Movement Type", moveTypeNames[SavedInfo.moveType] or "Unknown", Color(220, 220, 220) })

        if SavedInfo.activeWeapon then
            table.insert(data.equipment, { "Active Weapon", SavedInfo.activeWeapon, Color(255, 200, 200) })
        end

        if SavedInfo.inventory and type(SavedInfo.inventory) == "table" and next(SavedInfo.inventory) then
            local items = SavedInfo.inventory
            if #items > 8 then
                local categories = {}
                for _, item in ipairs(items) do
                    local itemType = string.match(item, "^([%w_]+)") or "misc"
                    categories[itemType] = (categories[itemType] or 0) + 1
                end

                local summary = {}
                for category, count in pairs(categories) do
                    table.insert(summary, category .. " (" .. count .. ")")
                end
                table.insert(data.equipment, { "Inventory", table.concat(summary, ", "), Color(200, 255, 200) })
            else
                table.insert(data.equipment, { "Inventory", table.concat(items, ", "), Color(200, 255, 200) })
            end
        end

        if SavedInfo.ammo and type(SavedInfo.ammo) == "table" and next(SavedInfo.ammo) then
            local ammo = SavedInfo.ammo
            if #ammo > 8 then
                local totalCount = #ammo
                local sample = {}
                for i = 1, math.min(5, #ammo) do table.insert(sample, ammo[i]) end
                table.insert(data.equipment, { "Ammo", table.concat(sample, ", ") ..
                string.format(" (+%d types)", totalCount - #sample), Color(200, 200, 255) })
            else
                table.insert(data.equipment, { "Ammo", table.concat(ammo, ", "), Color(200, 200, 255) })
            end
        end

        if SavedInfo.entities and type(SavedInfo.entities) == "table" and next(SavedInfo.entities) then
            local entityCount = #SavedInfo.entities

            if entityCount > 10 then
                local classes = {}
                for _, entity in ipairs(SavedInfo.entities) do
                    classes[entity.class] = (classes[entity.class] or 0) + 1
                end

                local topClasses = {}
                for class, count in pairs(classes) do
                    table.insert(topClasses, { class = class, count = count })
                end
                table.sort(topClasses, function(a, b) return a.count > b.count end)

                local displayCount = math.min(5, #topClasses)
                local summary = {}
                for i = 1, displayCount do
                    table.insert(summary, topClasses[i].class .. " (" .. topClasses[i].count .. ")")
                end
                table.insert(data.entities, {
                    "Entités par type",
                    table.concat(summary, ", ") ..
                    (#topClasses > displayCount and string.format(" (+%d autres types)", #topClasses - displayCount) or ""),
                    Color(255, 220, 220)
                })
                table.insert(data.entities, { "Total", entityCount, Color(255, 180, 180) })
            else
                local entityClasses = table.map(SavedInfo.entities, function(entity) return entity.class end)
                table.insert(data.entities, { "Entities", table.concat(entityClasses, ", "), Color(255, 220, 220) })
                table.insert(data.entities, { "Total", entityCount, Color(255, 180, 180) })
            end
        end

        if SavedInfo.npcs and type(SavedInfo.npcs) == "table" and next(SavedInfo.npcs) then
            local npcCount = #SavedInfo.npcs

            if npcCount > 10 then
                local classes = {}
                for _, npc in ipairs(SavedInfo.npcs) do
                    classes[npc.class] = (classes[npc.class] or 0) + 1
                end

                local topClasses = {}
                for class, count in pairs(classes) do
                    table.insert(topClasses, { class = class, count = count })
                end
                table.sort(topClasses, function(a, b) return a.count > b.count end)

                local displayCount = math.min(5, #topClasses)
                local summary = {}
                for i = 1, displayCount do
                    table.insert(summary, topClasses[i].class .. " (" .. topClasses[i].count .. ")")
                end

                table.insert(data.entities, {
                    "NPCs par type",
                    table.concat(summary, ", ") ..
                    (#topClasses > displayCount and string.format(" (+%d autres types)", #topClasses - displayCount) or ""),
                    Color(220, 255, 220)
                })
                table.insert(data.entities, { "Total NPCs", npcCount, Color(200, 255, 200) })
            else
                local npcClasses = table.map(SavedInfo.npcs, function(npc) return npc.class end)
                table.insert(data.entities, { "NPCs", table.concat(npcClasses, ", "), Color(220, 255, 220) })
                table.insert(data.entities, { "Total NPCs", npcCount, Color(200, 255, 200) })
            end
        end

        if SavedInfo.vehicles and type(SavedInfo.vehicles) == "table" and next(SavedInfo.vehicles) then
            local vehicleCount = #SavedInfo.vehicles

            if vehicleCount > 5 then
                local vehicleTypes = {}
                for _, vehicle in ipairs(SavedInfo.vehicles) do
                    vehicleTypes[vehicle] = (vehicleTypes[vehicle] or 0) + 1
                end

                local summary = {}
                for type, count in pairs(vehicleTypes) do
                    if count > 1 then
                        table.insert(summary, type .. " (" .. count .. ")")
                    else
                        table.insert(summary, type)
                    end
                end

                if #summary > 3 then
                    table.insert(data.entities, {
                        "Véhicules",
                        string.format("%d véhicules de %d types", vehicleCount, #summary),
                        Color(220, 220, 255)
                    })
                else
                    table.insert(data.entities, {
                        "Véhicules",
                        table.concat(summary, ", "),
                        Color(220, 220, 255)
                    })
                end
            else
                table.insert(data.entities, { "Vehicles", table.concat(SavedInfo.vehicles, ", "), Color(220, 220, 255) })
            end
            table.insert(data.entities, { "Total véhicules", vehicleCount, Color(200, 200, 255) })
        end

        table.insert(data.stats, { "Health", SavedInfo.health or "N/A", Color(255, 180, 180) })
        table.insert(data.stats, { "Armor", SavedInfo.armor or "N/A", Color(180, 180, 255) })
    else
        table.insert(data.basic, { "Player", ply:Nick(), Color(255, 255, 255) })
        table.insert(data.basic, { "Status", "No saved data", Color(255, 100, 100) })
    end

    return data
end

local function drawPhantomInfo(phantomData, playerPos, mapName)
    local phantom, ply = phantomData.phantom, phantomData.ply
    if not (IsValid(phantom) and IsValid(ply)) then return end

    local steamID = ply:SteamID()
    local phantomPos = phantom:GetPos()

    local distanceSqr = playerPos:DistToSqr(phantomPos)
    if distanceSqr > 250000 then
        phantomInfoCache[steamID] = nil
        return
    end

    local now = CurTime()
    if not phantomInfoCache[steamID] or phantomInfoCache[steamID].expires < now then
        SavedInfo = (RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID])
        phantomInfoCache[steamID] = {
            data = buildPhantomInfoData(ply, SavedInfo, mapName),
            expires = now + CACHE_LIFETIME,
            activeCategory = phantomInfoCache[steamID] and phantomInfoCache[steamID].activeCategory or "basic"
        }
    end

    local infoData = phantomInfoCache[steamID].data
    local activeCategory = phantomInfoCache[steamID].activeCategory
    local pos = phantomPos + Vector(0, 0, 80)
    local ang = Angle(0, LocalPlayer():EyeAngles().yaw - 90, 90)

    local hoverScale = phantomInfoCache[steamID].hoverScale or 1.0

    local theme = {
        background = Color(20, 20, 30, 220),
        header = Color(30, 30, 45, 255),
        border = Color(70, 130, 180, 255),
        text = Color(220, 220, 255),
        highlight = Color(100, 180, 255)
    }

    local scale = 0.1 * hoverScale
    surface.SetFont("Trebuchet24")
    local infoCategoryHeight = 30
    local titleHeight = 35
    local lineHeight = 20
    local textPadding = 15
    local panelWidth = 350

    local panelHeight = titleHeight + infoCategoryHeight
    local categoryContent = infoData[activeCategory]
    panelHeight = panelHeight + (#categoryContent * lineHeight) + 20

    local offsetX = -panelWidth / 2
    local offsetY = -panelHeight / 2

    cam.Start3D2D(pos, ang, scale)

    draw.RoundedBox(8, offsetX, offsetY, panelWidth, panelHeight, theme.background)

    for i = 0, 2 do
        local borderColor = Color(
            theme.border.r,
            theme.border.g,
            theme.border.b,
            255 - i * 40
        )
        surface.SetDrawColor(borderColor)
        surface.DrawOutlinedRect(offsetX - i, offsetY - i, panelWidth + i * 2, panelHeight + i * 2, 1)
    end

    local title = "Phantom of " .. ply:Nick()
    surface.SetDrawColor(theme.header)
    surface.DrawRect(offsetX, offsetY, panelWidth, titleHeight)

    draw.SimpleText(title, "Trebuchet24", offsetX + (panelWidth / 2) + 1, offsetY + (titleHeight / 2) + 1,
        Color(0, 0, 0, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(title, "Trebuchet24", offsetX + (panelWidth / 2), offsetY + (titleHeight / 2),
        theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local tabWidth = panelWidth / #PHANTOM_CATEGORIES
    local tabY = offsetY + titleHeight

    for i, categoryInfo in ipairs(PHANTOM_CATEGORIES) do
        local catID, catName, catColor = categoryInfo[1], categoryInfo[2], categoryInfo[3]
        local tabX = offsetX + (i - 1) * tabWidth
        local isActive = (catID == activeCategory)

        local tabHoverAmount = phantomInfoCache[steamID].tabHover and phantomInfoCache[steamID].tabHover[i] or 0

        local r = isActive and catColor.r / 2 or Lerp(tabHoverAmount, 40, catColor.r / 3)
        local g = isActive and catColor.g / 2 or Lerp(tabHoverAmount, 40, catColor.g / 3)
        local b = isActive and catColor.b / 2 or Lerp(tabHoverAmount, 40, catColor.b / 3)

        surface.SetDrawColor(r, g, b, 200)
        surface.DrawRect(tabX, tabY, tabWidth, infoCategoryHeight)

        if isActive then
            for j = 0, 2 do
                local alpha = 255 - j * 50
                surface.SetDrawColor(catColor.r, catColor.g, catColor.b, alpha)
                surface.DrawOutlinedRect(tabX + j, tabY + j, tabWidth - j * 2, infoCategoryHeight - j * 2, 1)
            end

            local triSize = 8
            draw.NoTexture()
            surface.SetDrawColor(catColor)
            surface.DrawPoly({
                { x = tabX + tabWidth / 2 - triSize, y = tabY + infoCategoryHeight },
                { x = tabX + tabWidth / 2 + triSize, y = tabY + infoCategoryHeight },
                { x = tabX + tabWidth / 2,           y = tabY + infoCategoryHeight + triSize }
            })
        end

        local textColor = isActive and Color(255, 255, 255) or
            Color(Lerp(tabHoverAmount, 180, 220), Lerp(tabHoverAmount, 180, 220), Lerp(tabHoverAmount, 180, 220))

        draw.SimpleText(catName, "Trebuchet18", tabX + (tabWidth / 2), tabY + (infoCategoryHeight / 2),
            textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        if distanceSqr < 90000 then
            local mousePosX, mousePosY = input.GetCursorPos()
            local x, y = cam.WorldToScreen(pos)
            if mousePosX and mousePosY and x and y then
                local screenX = x - panelWidth / 2 * scale + (i - 1) * tabWidth * scale
                local screenY = y - panelHeight / 2 * scale + titleHeight * scale
                local screenW = tabWidth * scale
                local screenH = infoCategoryHeight * scale

                local isHovering = (mousePosX >= screenX and mousePosX <= screenX + screenW and
                    mousePosY >= screenY and mousePosY <= screenY + screenH)

                phantomInfoCache[steamID].tabHover = phantomInfoCache[steamID].tabHover or {}

                if isHovering then
                    phantomInfoCache[steamID].tabHover[i] = math.min(
                        (phantomInfoCache[steamID].tabHover[i] or 0) + FrameTime() * 5, 1)
                    phantomInfoCache[steamID].hoverScale = Lerp(FrameTime() * 3,
                        phantomInfoCache[steamID].hoverScale or 1, 1.05)

                    if input.IsMouseDown(MOUSE_LEFT) then
                        phantomInfoCache[steamID].activeCategory = catID
                    end
                else
                    phantomInfoCache[steamID].tabHover[i] = math.max(
                        (phantomInfoCache[steamID].tabHover[i] or 0) - FrameTime() * 5, 0)
                end
            end
        end
    end

    local contentY = tabY + infoCategoryHeight + 10
    for i, lineData in ipairs(categoryContent) do
        local label, value, color = lineData[1], lineData[2], lineData[3]

        local fadeInTime = i * 0.05
        local alpha = math.min((CurTime() - (phantomInfoCache[steamID].categoryChanged or 0) - fadeInTime) * 5, 1)
        if alpha < 0 then alpha = 0 end

        draw.SimpleText(label .. ":", "Trebuchet18", offsetX + textPadding, contentY + (i - 1) * lineHeight,
            Color(200, 200, 200, 200 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local valueText = tostring(value)
        if #valueText > 40 then
            valueText = string.sub(valueText, 1, 37) .. "..."
        end

        local valueColor = color or Color(255, 255, 255)
        valueColor = Color(valueColor.r, valueColor.g, valueColor.b, valueColor.a * alpha)

        draw.SimpleText(valueText, "Trebuchet18", offsetX + textPadding + 120, contentY + (i - 1) * lineHeight,
            valueColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    cam.End3D2D()
end

hook.Add("PostDrawOpaqueRenderables", "DrawPlayerPhantomInfo", function()
    reloadSavedData()
    local playerPos = LocalPlayer():GetPos()
    local mapName = game.GetMap()

    local shouldRefresh = false
    if RARELOAD.playerPositions and RARELOAD.playerPositions[mapName] then
        for steamID, _ in pairs(RARELOAD.playerPositions[mapName]) do
            if not RARELOAD.Phantom[steamID] or not IsValid(RARELOAD.Phantom[steamID].phantom) then
                shouldRefresh = true
                break
            end
        end
    end

    if shouldRefresh then
        RARELOAD.RefreshPhantoms()
    end

    if RARELOAD.settings.debugEnabled then
        for _, data in pairs(RARELOAD.Phantom) do
            if IsValid(data.phantom) then
                drawPhantomInfo(data, playerPos, mapName)
            end
        end
    end
end)

hook.Add("Think", "CheckDebugModeChanges", function()
    local currentDebugState = RARELOAD.settings.debugEnabled

    if RARELOAD.lastDebugState ~= currentDebugState then
        updatePhantomVisibility()
        RARELOAD.lastDebugState = currentDebugState
    end

    if RARELOAD.nextPhantomCheck and RARELOAD.nextPhantomCheck > CurTime() then return end

    local shouldRefresh = false
    for steamID, data in pairs(RARELOAD.playerPositions[game.GetMap()] or {}) do
        if not RARELOAD.Phantom[steamID] or not IsValid(RARELOAD.Phantom[steamID].phantom) then
            shouldRefresh = true
            break
        end
    end

    if shouldRefresh then
        RARELOAD.RefreshPhantoms()
    end

    RARELOAD.nextPhantomCheck = CurTime() + 2
end)

hook.Add("PlayerDisconnected", "RemovePhantomOnDisconnect", function(ply)
    if IsValid(ply) then
        removePhantom(ply:SteamID())
    end
end)
