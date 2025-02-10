RARELOAD = RARELOAD or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}
RARELOAD.settings = RARELOAD.settings
RARELOAD.Phanthom = RARELOAD.Phanthom or {}

local function createPhantom(ply, pos, ang)
    local phantom = ents.CreateClientProp(ply:GetModel())
    phantom:SetPos(pos)
    phantom:SetAngles(ang)
    phantom:SetRenderMode(RENDERMODE_TRANSALPHA)
    phantom:SetColor(Color(255, 255, 255, 150))
    phantom:Spawn()
    phantom:SetMoveType(MOVETYPE_NONE)
    phantom:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    return phantom
end

local function removePhantom(steamID)
    local existingPhantom = RARELOAD.Phanthom[steamID] and RARELOAD.Phanthom[steamID].phantom
    if IsValid(existingPhantom) then
        existingPhantom:Remove()
    end
    RARELOAD.Phanthom[steamID] = nil
end

local function handleNetReceive(event, callback)
    net.Receive(event, callback)
end

handleNetReceive("SyncData", function()
    local data = net.ReadTable()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = data.playerPositions
    RARELOAD.settings = data.settings
    RARELOAD.Phanthom = data.Phanthom or {}
end)

handleNetReceive("CreatePlayerPhantom", function()
    local ply = net.ReadEntity()
    local pos = net.ReadVector()
    local ang = net.ReadAngle()

    if not pos:IsZero() then
        ---@diagnostic disable-next-line: undefined-field
        removePhantom(ply:SteamID())
        if RARELOAD.settings.debugEnabled then
            ---@diagnostic disable-next-line: undefined-field
            RARELOAD.Phanthom[ply:SteamID()] = { phantom = createPhantom(ply, pos, ang), ply = ply }
        end
    else
        print("[RARELOAD DEBUG] Invalid position or angle for phantom creation.")
    end
end)

function RARELOAD.RefreshPhantoms()
    if not RARELOAD.settings.debugEnabled then return end

    local currentMap = game.GetMap()
    for steamID, savedData in pairs(RARELOAD.playerPositions[currentMap] or {}) do
        if not RARELOAD.Phanthom[steamID] then
            RARELOAD.Phanthom[steamID] = {
                phantom = createPhantom(
                    { GetModel = function() return savedData.model or "models/player.mdl" end },
                    savedData.pos, savedData.ang
                )
            }
        end
    end
end

handleNetReceive("RemovePlayerPhantom", function()
    local ply = net.ReadEntity()
    ---@diagnostic disable-next-line: undefined-field
    removePhantom(ply:SteamID())
end)

local fileNotExistPrinted = false
local function reloadSavedData()
    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".json"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        if data then
            local status, result = pcall(util.JSONToTable, data)
            if status then
                RARELOAD.playerPositions = result
            else
                print("[RARELOAD DEBUG] Error parsing JSON: " .. result)
            end
        else
            print("[RARELOAD DEBUG] File is empty: " .. filePath)
        end
    elseif not fileNotExistPrinted then
        print("[RARELOAD DEBUG] File does not exist: " .. filePath)
        fileNotExistPrinted = true
    end
end

local function AngleToString(angle)
    return string.format("[%.2f, %.2f, %.2f]", angle[1], angle[2], angle[3])
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

local function drawPhantomInfo(phantomData, playerPos, mapName)
    local phantom, ply = phantomData.phantom, phantomData.ply
    if not (IsValid(phantom) and IsValid(ply)) then return end

    local phantomPos = phantom:GetPos()
    if playerPos:Distance(phantomPos) > 500 then return end

    local pos = phantomPos + Vector(0, 0, 80)
    local ang = Angle(0, LocalPlayer():EyeAngles().yaw - 90, 90)

    surface.SetFont("DermaDefaultBold")
    local textPadding, textSpacing, lineHeight = 10, 4, 15
    local panelWidth = 0
    local panelHeight = textPadding * 2
    local linesToDraw = {}

    local function addLine(title, value)
        local text = title .. ": " .. tostring(value)
        local textWidth = surface.GetTextSize(text)
        panelWidth = math.max(panelWidth, textWidth + textPadding * 2)
        panelHeight = panelHeight + lineHeight + textSpacing
        table.insert(linesToDraw, text)
    end

    SavedInfo = (RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][ply:SteamID()])
    if SavedInfo then
        addLine("Info", "Phantom de " .. ply:Nick())
        addLine("Saved Position", SavedInfo.pos)
        addLine("Eye Angles", AngleToString(SavedInfo.ang))
        addLine("Move Type", moveTypeNames[SavedInfo.moveType])
        addLine("Active Weapon", SavedInfo.activeWeapon)
        addLine("Inventory", table.concat(SavedInfo.inventory, ", "))
        addLine("Model", SavedInfo.model)
        addLine("Saved Entities", table.concat(SavedInfo.entities, ", "))
        addLine("Saved NPCs", table.concat(SavedInfo.npcs, ", "))
        addLine("Saved Vehicles", table.concat(SavedInfo.vehicles, ", "))
        addLine("Saved Ammo", table.concat(SavedInfo.ammo, ", "))
        addLine("Saved Health", table.concat(SavedInfo.health, ", "))
        addLine("Saved Armor", table.concat(SavedInfo.armor, ", "))
    else
        addLine("Spawn Point", "No Data")
    end

    local offsetX = -panelWidth / 2
    local offsetY = -panelHeight / 2

    cam.Start3D2D(pos, ang, 0.1)
    draw.RoundedBox(8, offsetX, offsetY, panelWidth, panelHeight, Color(30, 30, 30, 220))
    surface.SetDrawColor(80, 80, 80, 255)
    surface.DrawOutlinedRect(offsetX, offsetY, panelWidth, panelHeight)

    local y = offsetY + textPadding
    for _, text in ipairs(linesToDraw) do
        draw.SimpleText(text, "DermaDefaultBold", offsetX + textPadding, y, Color(255, 255, 255), TEXT_ALIGN_LEFT,
            TEXT_ALIGN_TOP)
        y = y + lineHeight + textSpacing
    end
    cam.End3D2D()
end

hook.Add("PostDrawOpaqueRenderables", "DrawPlayerPhantomInfo", function()
    reloadSavedData()
    local playerPos = LocalPlayer():GetPos()
    local mapName = game.GetMap()

    for _, data in pairs(RARELOAD.Phanthom) do
        drawPhantomInfo(data, playerPos, mapName)
    end
end)
