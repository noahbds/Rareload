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
    if RARELOAD.Phanthom[steamID] then
        local existingPhantom = RARELOAD.Phanthom[steamID].phantom
        if IsValid(existingPhantom) then
            existingPhantom:Remove()
        end
        RARELOAD.Phanthom[steamID] = nil
    end
end

net.Receive("SyncData", function()
    local data = net.ReadTable()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = data.playerPositions
    RARELOAD.settings = data.settings
    RARELOAD.Phanthom = data.Phanthom or {}
end)

net.Receive("CreatePlayerPhantom", function()
    local ply = net.ReadEntity()
    local pos = net.ReadVector()
    local ang = net.ReadAngle()

    if not pos:IsZero() then
        removePhantom(ply:SteamID())

        if RARELOAD.settings.debugEnabled then
            RARELOAD.Phanthom[ply:SteamID()] = { phantom = createPhantom(ply, pos, ang), ply = ply }
        end
    else
        print("[RARELOAD DEBUG] Invalid position or angle for phantom creation.")
    end
end)

function RARELOAD.RefreshPhantoms()
    if not RARELOAD.settings.debugEnabled then return end

    for steamID, savedData in pairs(RARELOAD.playerPositions[game.GetMap()] or {}) do
        if not RARELOAD.Phanthom[steamID] then
            RARELOAD.Phanthom[steamID] = {
                phantom = createPhantom(savedData.model or "models/player.mdl", savedData.pos,
                    savedData.ang)
            }
        end
    end
end

net.Receive("RemovePlayerPhantom", function()
    local ply = net.ReadEntity()
    removePhantom(ply:SteamID())
end)

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
    else
        print("[RARELOAD DEBUG] File does not exist: " .. filePath)
    end
end

local function AngleToString(angle)
    return string.format("[%.2f, %.2f, %.2f]", angle[1], angle[2], angle[3])
end

local function drawTextLine(label, value, panelWidth, panelHeight, textSpacing)
    if value and value ~= "" then
        local text = label .. ": " .. value
        local textWidth, textHeight = surface.GetTextSize(text)
        panelWidth = math.max(panelWidth, textWidth + 20)
        panelHeight = panelHeight + textHeight + textSpacing
        return true, text, textHeight, panelWidth, panelHeight
    end
    return false, nil, 0, panelWidth, panelHeight
end

hook.Add("PostDrawOpaqueRenderables", "DrawPlayerPhantomInfo", function()
    reloadSavedData()
    for _, data in pairs(RARELOAD.Phanthom) do
        local phantom = data.phantom
        local ply = data.ply

        if IsValid(phantom) and IsValid(ply) then
            local playerPos = LocalPlayer():GetPos()
            local phantomPos = phantom:GetPos()
            local distance = playerPos:Distance(phantomPos)

            if distance <= 500 then
                local pos = phantomPos + Vector(0, 0, 80)
                local ang = Angle(0, LocalPlayer():EyeAngles().yaw - 90, 90)

                surface.SetFont("DermaDefaultBold")
                local panelWidth = 0
                local panelHeight = 10
                local textSpacing = 2

                local linesToDraw = {}
                local yPos = 5

                local mapName = game.GetMap()
                local savedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][ply:SteamID()]

                if savedInfo then
                    local shouldDraw, text, textHeight
                    shouldDraw, text, textHeight, panelWidth, panelHeight = drawTextLine("Info",
                        "Phantom of " .. ply:Nick(), panelWidth, panelHeight, textSpacing)
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end

                    shouldDraw, text, textHeight, panelWidth, panelHeight = drawTextLine("Saved Position",
                        tostring(savedInfo.pos), panelWidth, panelHeight, textSpacing)
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end

                    shouldDraw, text, textHeight, panelWidth, panelHeight = drawTextLine("Eye Angles",
                        AngleToString(savedInfo.ang), panelWidth, panelHeight, textSpacing)
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end

                    shouldDraw, text, textHeight, panelWidth, panelHeight = drawTextLine("Move Type",
                        tostring(savedInfo.moveType), panelWidth, panelHeight, textSpacing)
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end

                    shouldDraw, text, textHeight, panelWidth, panelHeight = drawTextLine("Active Weapon",
                        tostring(savedInfo.activeWeapon), panelWidth, panelHeight, textSpacing)
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end

                    shouldDraw, text, textHeight, panelWidth, panelHeight = drawTextLine("Inventory",
                        table.concat(savedInfo.inventory, ", "), panelWidth, panelHeight, textSpacing)
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end
                else
                    local shouldDraw, text, textHeight
                    shouldDraw, text, textHeight, panelWidth, panelHeight = drawTextLine("Spawn Point", "No Data",
                        panelWidth, panelHeight, textSpacing)
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end
                end

                local offsetX = -panelWidth / 2
                local offsetY = -panelHeight / 2

                cam.Start3D2D(pos, ang, 0.1)
                surface.SetDrawColor(50, 50, 50, 200)
                surface.DrawRect(offsetX, offsetY, panelWidth, panelHeight)

                for _, lineData in ipairs(linesToDraw) do
                    local line, yPos = unpack(lineData)
                    draw.SimpleText(line, "DermaDefaultBold", offsetX + 10, offsetY + yPos, Color(255, 255, 255),
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end

                cam.End3D2D()
            end
        end
    end
end)
