RARELOAD = RARELOAD or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}
RARELOAD.settings = RARELOAD.settings
RARELOAD.Phanthom = RARELOAD.Phanthom or {}

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
        if RARELOAD.Phanthom[ply:SteamID()] then
            local existingPhantom = RARELOAD.Phanthom[ply:SteamID()].phantom
            if IsValid(existingPhantom) then
                existingPhantom:Remove()
            end
            RARELOAD.Phanthom[ply:SteamID()] = nil
        end

        -- Create a new phantom
        local phantom = ents.CreateClientProp(ply:GetModel())
        phantom:SetPos(pos)
        phantom:SetAngles(ang)
        phantom:SetRenderMode(RENDERMODE_TRANSALPHA)
        phantom:SetColor(Color(255, 255, 255, 150))
        phantom:Spawn()

        phantom:SetMoveType(MOVETYPE_NONE)
        phantom:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)

        RARELOAD.Phanthom[ply:SteamID()] = { phantom = phantom, ply = ply }
    else
        print("[RARELOAD DEBUG] Invalid position or angle for phantom creation.")
    end
end)

net.Receive("RemovePlayerPhantom", function()
    local ply = net.ReadEntity()
    if RARELOAD.Phanthom[ply:SteamID()] then
        local existingPhantom = RARELOAD.Phanthom[ply:SteamID()].phantom
        if IsValid(existingPhantom) then
            existingPhantom:Remove()
        end
        RARELOAD.Phanthom[ply:SteamID()] = nil
    end
end)

hook.Add("PostDrawOpaqueRenderables", "DrawPlayerPhantomInfo", function()
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

                local function drawTextLine(label, value)
                    if value and value ~= "" then
                        local text = label .. ": " .. value
                        local textWidth, textHeight = surface.GetTextSize(text)
                        panelWidth = math.max(panelWidth, textWidth + 20)
                        panelHeight = panelHeight + textHeight + textSpacing
                        return true, text, textHeight
                    end
                    return false, nil, 0
                end

                local linesToDraw = {}
                local yPos = 5

                local mapName = game.GetMap()
                local savedInfo = RARELOAD.playerPositions[mapName] and
                    RARELOAD.playerPositions[mapName][ply:SteamID()]

                if savedInfo then
                    local shouldDraw, text, textHeight = drawTextLine("Info",
                        "This is a phantom of " .. ply:Nick() .. ", where the player position was last saved.")
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end

                    shouldDraw, text, textHeight = drawTextLine("Saved Position", tostring(savedInfo.pos))
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end

                    shouldDraw, text, textHeight = drawTextLine("Eye Angles", tostring(savedInfo.ang))
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end

                    shouldDraw, text, textHeight = drawTextLine("Move Type", tostring(savedInfo.moveType))
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end

                    shouldDraw, text, textHeight = drawTextLine("Active Weapon", tostring(savedInfo.activeWeapon))
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end

                    shouldDraw, text, textHeight = drawTextLine("Inventory", table.concat(savedInfo.inventory, ", "))
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end
                else
                    local shouldDraw, text, textHeight = drawTextLine("Spawn Point", "No Data")
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
