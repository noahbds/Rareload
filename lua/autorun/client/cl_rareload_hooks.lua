RARELOAD = RARELOAD or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.Phantom = RARELOAD.Phantom or {}

function HandleNetReceive(event, callback)
    net.Receive(event, function(len, ply)
        if not IsValid(ply) then return end
        callback()
    end)
end

function CreatePhantom(ply, pos, ang)
    if not IsValid(ply) then return end

    local phantom = ClientsideModel(ply:GetModel())
    phantom:SetPos(pos)

    local correctedAng
    if ang then
        correctedAng = Angle(0, ang.y, 0)
    else
        correctedAng = Angle(0, ply:GetAngles().y, 0)
    end

    phantom:SetAngles(correctedAng)
    ---@diagnostic disable-next-line: inject-field
    phantom.isPhantom = true
    phantom:SetRenderMode(RENDERMODE_TRANSALPHA)
    phantom:SetColor(Color(255, 255, 255, 100))

    phantom:SetMoveType(MOVETYPE_NONE)
    phantom:SetSolid(SOLID_NONE)

    if RARELOAD.settings.debugEnabled then
        phantom:SetColor(Color(255, 255, 255, 150))
        phantom:SetNoDraw(false)
    else
        phantom:SetColor(Color(0, 0, 0, 0))
        phantom:SetNoDraw(true)
    end

    return phantom
end

function UpdatePhantomVisibility()
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

function RemovePhantom(steamID)
    if not steamID then return end

    local phantomData = RARELOAD.Phantom[steamID]
    if phantomData then
        if IsValid(phantomData.phantom) then
            print("[RARELOAD DEBUG] Removing phantom for player " .. steamID)
            phantomData.phantom:Remove()
            SafeRemoveEntity(phantomData.phantom)
        end
        RARELOAD.Phantom[steamID] = nil
    end
end

function UpdatePhantomPosition(steamID, pos, ang)
    local phantomData = RARELOAD.Phantom[steamID]
    if phantomData and IsValid(phantomData.phantom) then
        phantomData.phantom:SetPos(pos)
        phantomData.phantom:SetAngles(Angle(0, ang.y, 0))
    end
end

net.Receive("UpdatePhantomPosition", function()
    local steamID = net.ReadString()
    local pos = net.ReadVector()
    local ang = net.ReadAngle()
    UpdatePhantomPosition(steamID, pos, ang)
end)

HandleNetReceive("SyncData", function()
    local data = net.ReadTable()
    if not data or type(data) ~= "table" then return end

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = data.playerPositions or {}

    local oldDebugEnabled = RARELOAD.settings.debugEnabled
    RARELOAD.settings = data.settings or {}
    RARELOAD.Phantom = data.Phantom or {}

    if oldDebugEnabled ~= RARELOAD.settings.debugEnabled then
        UpdatePhantomVisibility()
    end
end)

HandleNetReceive("CreatePlayerPhantom", function()
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

    RemovePhantom(steamID)

    RARELOAD.Phantom[steamID] = {
        phantom = CreatePhantom(ply, pos, ang),
        ply = ply
    }
end)

HandleNetReceive("RemovePlayerPhantom", function()
    local ply = net.ReadEntity()
    if IsValid(ply) then
        ---@diagnostic disable-next-line: undefined-field
        RemovePhantom(ply:SteamID())
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

local phantomInteractionMode = false
local phantomInteractionTarget = nil

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
    if not ang or not ang.p or not ang.y or not ang.r then
        return "N/A"
    end
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
        table.insert(data.position,
            { "Direction", SavedInfo.ang and AngleToString(SavedInfo.ang) or "N/A", Color(220, 220, 220) })
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
    local maxDistance = (phantomInteractionMode and phantomInteractionTarget == steamID) and 500000 or 250000

    if distanceSqr > maxDistance then
        phantomInfoCache[steamID] = nil
        if phantomInteractionTarget == steamID then
            phantomInteractionMode = false
            phantomInteractionTarget = nil
        end
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

    local ang
    if phantomInteractionMode and phantomInteractionTarget == steamID then
        ang = Angle(0, LocalPlayer():EyeAngles().yaw - 90, 90)
    else
        local playerToPhantom = phantomPos - playerPos
        playerToPhantom:Normalize()
        ang = playerToPhantom:Angle()
        ang.y = ang.y - 90
        ang.p = 0
        ang.r = 90
    end

    local hoverScale = phantomInfoCache[steamID].hoverScale or 1.0

    local interactionBonus = (phantomInteractionMode and phantomInteractionTarget == steamID) and 1.5 or 1.0

    local theme = {
        background = Color(20, 20, 30, 220),
        header = Color(30, 30, 45, 255),
        border = Color(70, 130, 180, 255),
        text = Color(220, 220, 255),
        highlight = Color(100, 180, 255)
    }

    local scale = 0.1 * hoverScale * interactionBonus
    surface.SetFont("Trebuchet24")
    local infoCategoryHeight = 30
    local titleHeight = 35
    local lineHeight = 22
    local textPadding = 15

    local contentWidth = 350
    local categoryContent = infoData[activeCategory]

    for _, lineData in ipairs(categoryContent) do
        local label, value = lineData[1], tostring(lineData[2])
        local labelWidth = surface.GetTextSize(label .. ":")
        local valueWidth = surface.GetTextSize(value)
        local totalWidth = labelWidth + valueWidth + 140
        contentWidth = math.max(contentWidth, totalWidth)
    end

    local panelWidth = math.min(contentWidth, 500)

    local panelHeight = titleHeight + infoCategoryHeight
    panelHeight = panelHeight + (#categoryContent * lineHeight) + 20

    local offsetX = -panelWidth / 2
    local offsetY = -panelHeight / 2

    local screenPos = pos:ToScreen()
    local screenX, screenY = screenPos.x, screenPos.y

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

    local title = "Phantom de " .. ply:Nick()
    surface.SetDrawColor(theme.header)
    surface.DrawRect(offsetX, offsetY, panelWidth, titleHeight)

    draw.SimpleText(title, "Trebuchet24", offsetX + (panelWidth / 2) + 1, offsetY + (titleHeight / 2) + 1,
        Color(0, 0, 0, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(title, "Trebuchet24", offsetX + (panelWidth / 2), offsetY + (titleHeight / 2),
        theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    if phantomInteractionMode and phantomInteractionTarget == steamID then
        local interactText = "Mode Interaction [E pour quitter]"
        draw.SimpleText(interactText, "Trebuchet18", offsetX + (panelWidth / 2), offsetY + titleHeight - 2,
            Color(255, 255, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    end

    local tabWidth = panelWidth / #PHANTOM_CATEGORIES
    local tabY = offsetY + titleHeight

    local tabScreenInfo = {}

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

        local worldPos = LocalToWorld(Vector(tabX + tabWidth / 2, tabY + infoCategoryHeight / 2, 0), Angle(0, 0, 0), pos,
            ang)
        local screenTabPos = worldPos:ToScreen()

        table.insert(tabScreenInfo, {
            catID = catID,
            worldX = tabX + tabWidth / 2,
            worldY = tabY + infoCategoryHeight / 2,
            worldW = tabWidth,
            worldH = infoCategoryHeight
        })
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


    if phantomInteractionMode and phantomInteractionTarget == steamID then
        local mousePosX, mousePosY = input.GetCursorPos()
        local sw, sh = ScrW(), ScrH()

        if mousePosX and mousePosY then
            phantomInfoCache[steamID].tabHover = phantomInfoCache[steamID].tabHover or {}

            phantomInfoCache[steamID].panelInfo = {
                scale = scale,
                pos = pos,
                ang = ang,
                tabInfo = tabScreenInfo,
                offsetX = offsetX,
                offsetY = offsetY,
                panelWidth = panelWidth,
                panelHeight = panelHeight
            }

            local mouseWorldPos = util.MouseTo3D(mousePosX, mousePosY, sw, sh, 90, pos, ang, scale)
            local isHoveringAny = false

            if mouseWorldPos then
                local localX, localY = mouseWorldPos.x, mouseWorldPos.y

                local inPanel = (localX >= offsetX and localX <= offsetX + panelWidth and
                    localY >= offsetY and localY <= offsetY + panelHeight)

                for i, tabInfo in ipairs(tabScreenInfo) do
                    local tabLeft = offsetX + (i - 1) * tabWidth
                    local tabRight = tabLeft + tabWidth
                    local tabTop = tabY
                    local tabBottom = tabTop + infoCategoryHeight

                    local isHovering = (localX >= tabLeft and localX <= tabRight and
                        localY >= tabTop and localY <= tabBottom)

                    if isHovering then
                        isHoveringAny = true
                        phantomInfoCache[steamID].tabHover[i] = math.min(
                            (phantomInfoCache[steamID].tabHover[i] or 0) + FrameTime() * 5, 1)

                        if RARELOAD.settings.debugEnabled then
                            surface.SetDrawColor(255, 255, 0, 50)
                            surface.DrawRect(tabLeft, tabTop, tabWidth, infoCategoryHeight)
                        end
                    else
                        phantomInfoCache[steamID].tabHover[i] = math.max(
                            (phantomInfoCache[steamID].tabHover[i] or 0) - FrameTime() * 5, 0)
                    end
                end

                phantomInfoCache[steamID].hoverScale = Lerp(FrameTime() * 3,
                    phantomInfoCache[steamID].hoverScale or 1, isHoveringAny and 1.05 or 1)

                surface.SetDrawColor(255, 255, 255, 220)
                local cursorSize = 10

                surface.DrawLine(localX - cursorSize, localY, localX + cursorSize, localY)
                surface.DrawLine(localX, localY - cursorSize, localX, localY + cursorSize)

                local segments = 12
                local radius = cursorSize * 0.8
                local points = {}

                for i = 0, segments do
                    local angle = math.rad((i / segments) * 360)
                    points[i + 1] = {
                        x = localX + math.cos(angle) * radius,
                        y = localY + math.sin(angle) * radius
                    }
                end

                for i = 1, segments do
                    local p1 = points[i]
                    local p2 = points[i + 1] or points[1]
                    surface.DrawLine(p1.x, p1.y, p2.x, p2.y)
                end

                if isHoveringAny then
                    surface.SetDrawColor(255, 255, 100, 255)
                    surface.DrawRect(localX - 2, localY - 2, 4, 4)
                end
            end
        end
    else
        if distanceSqr < 90000 then
            local text = "Press [E] to interact"
            local _, textY = draw.SimpleText(text, "Trebuchet18", offsetX + (panelWidth / 2), offsetY + panelHeight + 15,
                Color(255, 255, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end
    cam.End3D2D()
end

hook.Add("GUIMousePressed", "PhantomPanelInteraction", function(mouseCode)
    if not phantomInteractionMode or not phantomInteractionTarget then return end
    if mouseCode ~= MOUSE_LEFT then return end

    local cache = phantomInfoCache[phantomInteractionTarget]
    if not cache or not cache.panelInfo then return end

    local panelInfo = cache.panelInfo
    local mousePosX, mousePosY = input.GetCursorPos()
    local sw, sh = ScrW(), ScrH()

    local mouseWorldPos = util.MouseTo3D(mousePosX, mousePosY, sw, sh, 90, panelInfo.pos, panelInfo.ang, panelInfo.scale)
    if not mouseWorldPos then return end

    if RARELOAD.settings.debugEnabled then
        Debugclick = { pos = mouseWorldPos, time = CurTime() + 2 }
    end

    for i, tabInfo in ipairs(panelInfo.tabInfo) do
        local tabLeft = panelInfo.offsetX + (i - 1) * (panelInfo.panelWidth / #PHANTOM_CATEGORIES)
        local tabWidth = panelInfo.panelWidth / #PHANTOM_CATEGORIES
        local tabRight = tabLeft + tabWidth
        local tabTop = panelInfo.offsetY + 35
        local tabBottom = tabTop + 30

        if mouseWorldPos.x >= tabLeft and mouseWorldPos.x <= tabRight and
            mouseWorldPos.y >= tabTop and mouseWorldPos.y <= tabBottom then
            local oldCategory = cache.activeCategory
            cache.activeCategory = PHANTOM_CATEGORIES[i][1]
            cache.categoryChanged = CurTime()

            if oldCategory ~= cache.activeCategory then
                surface.PlaySound("ui/buttonclick.wav")
            end

            return true
        end
    end
end)

function util.MouseTo3D(x, y, sw, sh, fov, pos, ang, scale)
    local start = EyePos()
    local dir = util.ScreenToVector(x, y)

    local planeNormal = ang:Up()
    local planePos = pos

    if not dir or not planeNormal then return nil end
    local denom = dir:Dot(planeNormal)
    if math.abs(denom) < 0.001 then return nil end

    local t = (planePos - start):Dot(planeNormal) / denom
    if t < 0 then return nil end

    local hitPos = start + dir * t
    local localPos = WorldToLocal(hitPos, Angle(0, 0, 0), pos, ang)
    return Vector(
        math.Round(localPos.x / scale, 3),
        math.Round(localPos.y / scale, 3),
        0
    )
end

local nativeAimVector = util.AimVector

function util.ScreenToVector(x, y)
    if nativeAimVector then
        local eyeAngles = EyeAngles()
        local sw, sh = ScrW(), ScrH()
        local fov = LocalPlayer():GetFOV()
        return nativeAimVector(eyeAngles, fov, x, y, sw, sh)
    end

    local screen_w, screen_h = ScrW(), ScrH()
    local ang = EyeAngles()

    local normalizedX = (x / screen_w) * 2 - 1
    local normalizedY = ((y / screen_h) * 2 - 1) * -1

    local forward = ang:Forward()
    local right = ang:Right()
    local up = ang:Up()

    local fov = math.rad(LocalPlayer():GetFOV())
    local tanFov = math.tan(fov / 2)
    local aspectRatio = screen_w / screen_h

    local dir = forward +
        right * (normalizedX * tanFov * aspectRatio) +
        up * (normalizedY * tanFov)

    return dir:GetNormalized()
end

if not util.IntersectRayWithPlane then
    function util.IntersectRayWithPlane(rayStart, rayDir, planePos, planeNormal)
        local denom = rayDir:Dot(planeNormal)
        if denom == 0 then return nil end

        local t = (planePos - rayStart):Dot(planeNormal) / denom
        if t < 0 then return nil end

        return rayStart + rayDir * t
    end
end

if not util.AimVector then
    function util.AimVector(eyeAngles, fov, x, y, sw, sh)
        if not x or not y then return nil end

        local fw = eyeAngles:Forward()
        local rt = eyeAngles:Right()
        local up = eyeAngles:Up()

        local xCenter = sw / 2
        local yCenter = sh / 2
        local xRatio = (x - xCenter) / xCenter
        local yRatio = (yCenter - y) / yCenter

        local fovRadians = math.rad(fov or 90)
        local xTan = math.tan(fovRadians / 2) * (sw / sh)
        local yTan = math.tan(fovRadians / 2)

        return (fw + rt * (xRatio * xTan) + up * (yRatio * yTan)):GetNormalized()
    end
end

hook.Add("KeyPress", "PhantomInteractionToggle", function(ply, key)
    if not IsValid(ply) or not ply:IsPlayer() or ply ~= LocalPlayer() then return end
    if key ~= IN_USE then return end

    local playerPos = ply:GetPos()
    local mapName = game.GetMap()

    if phantomInteractionMode then
        phantomInteractionMode = false
        phantomInteractionTarget = nil
        gui.EnableScreenClicker(false)
        return
    end

    local closestPhantom = nil
    local closestDistance = 10000

    for steamID, data in pairs(RARELOAD.Phantom) do
        if IsValid(data.phantom) and IsValid(data.ply) then
            local distance = playerPos:DistToSqr(data.phantom:GetPos())
            if distance < closestDistance then
                closestPhantom = steamID
                closestDistance = distance
            end
        end
    end

    if closestPhantom then
        phantomInteractionMode = true
        phantomInteractionTarget = closestPhantom
        gui.EnableScreenClicker(true)
    end
end)


function RARELOAD.RefreshPhantoms()
    local mapName = game.GetMap()

    if not RARELOAD.playerPositions or not RARELOAD.playerPositions[mapName] then
        return
    end

    -- Vérification que RARELOAD.Phantom existe
    if not RARELOAD.Phantom then
        RARELOAD.Phantom = {}
    end

    for steamID, playerData in pairs(RARELOAD.playerPositions[mapName]) do
        if not RARELOAD.Phantom[steamID] or not IsValid(RARELOAD.Phantom[steamID].phantom) then
            local ply = nil
            for _, p in ipairs(player.GetAll()) do
                if p:SteamID() == steamID then
                    ply = p
                    break
                end
            end

            if IsValid(ply) and playerData.pos then
                local ang = Angle(0, 0, 0)
                if playerData.ang then
                    if type(playerData.ang) == "table" then
                        ang = Angle(playerData.ang[1], playerData.ang[2], playerData.ang[3])
                    else
                        ang = playerData.ang
                    end
                end

                RARELOAD.Phantom[steamID] = {
                    phantom = CreatePhantom(ply, playerData.pos, ang),
                    ply = ply
                }

                -- Vérification que RARELOAD.settings existe avant d'accéder à debugEnabled
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    ---@diagnostic disable-next-line: need-check-nil, undefined-field
                    print("[RARELOAD DEBUG] Created phantom for " .. ply:Nick() .. " at " .. tostring(playerData.pos))
                end
            end
        end
    end
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
        UpdatePhantomVisibility()
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
        RemovePhantom(ply:SteamID())
    end
end)
