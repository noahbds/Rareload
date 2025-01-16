-- lua/autorun/server/sv_rareload_hooks.lua

hook.Add("ShutDown", "SavePlayerPosition", function()
    if not RARELOAD.settings.addonEnabled then return end

    EnsureFolderExists()

    local mapName = game.GetMap()
    file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
end)

hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    LoadAddonState()

    if RARELOAD.settings.debugEnabled then
        local settings = {
            { name = "addonEnabled",           message = "Respawn at Reload addon" },
            { name = "spawnModeEnabled",       message = "Spawn with saved move type" },
            { name = "autoSaveEnabled",        message = "Auto-save position" },
            { name = "retainInventory",        message = "Retain inventory" },
            { name = "nocustomrespawnatdeath", message = "No Custom Respawn at Death" },
            { name = "debugEnabled",           message = "Debug mode" }
        }

        for i, setting in ipairs(settings) do
            if RARELOAD.settings[setting.name] then
                print("[RARELOAD DEBUG] " .. setting.message .. " is enabled.")
            else
                print("[RARELOAD DEBUG] " .. setting.message .. " is disabled.")
            end
        end
    end

    if not RARELOAD.settings.addonEnabled then return end

    EnsureFolderExists()

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
end)

hook.Add("PlayerDisconnect", "SavePlayerPositionDisconnect", function(ply)
    if not RARELOAD.settings.addonEnabled then return end

    EnsureFolderExists()

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
    RARELOAD.playerPositions[mapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType(),
    }

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Player " ..
            ply:SteamID() ..
            " disconnected. Saved position: " .. tostring(RARELOAD.playerPositions[mapName][ply:SteamID()].pos))
        print("[RARELOAD DEBUG] Player " ..
            ply:SteamID() ..
            " disconnected. Saved move type: " .. tostring(RARELOAD.playerPositions[mapName][ply:SteamID()].moveType))
    end
end)

hook.Add("PlayerDeath", "SetWasKilledFlag", function(ply)
    ply.wasKilled = true
end)

hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
    if RARELOAD.settings.debugEnabled then
        DebugPlayerSpawnInfo(ply)
    end

    if not RARELOAD.settings.addonEnabled then
        GiveDefaultWeapons(ply)
        return
    end

    if RARELOAD.settings.nocustomrespawnatdeath and ply.wasKilled then
        ply.wasKilled = false
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Player was killed, resetting wasKilled flag")
        end
        return
    end

    local mapName = game.GetMap()
    local savedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][ply:SteamID()]

    if not savedInfo then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] No saved player info found")
        end
        return
    end

    local moveType = savedInfo.moveType
    if not moveType or not isnumber(moveType) then
        print("[RARELOAD DEBUG] Error: Invalid saved move type.")
        return
    end

    local spawnPoint = CreateSpawnPoint(ply, savedInfo)
    if spawnPoint then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD] Movetype not toggled, spawned entity to saved position to prevent incorrect respawn")
        end

        local validPos = spawnPoint:GetPos()
        ply:SetPos(validPos)
        savedInfo.pos = validPos

        RARELOAD.playerPositions[mapName][ply:SteamID()].pos = validPos
        SaveAddonState()

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD] Position from entity saved")
        end

        spawnPoint:Remove()
    else
        ply:SetPos(savedInfo.pos)
    end


    if not RARELOAD.settings.spawnModeEnabled then
        HandleSpawnModeDisabled(ply, savedInfo)
        SetPlayerPositionAndEyeAngles(ply, savedInfo)
    else
        SetPlayerPositionAndEyeAngles(ply, savedInfo)
    end

    if RARELOAD.settings.retainInventory and savedInfo.inventory then
        HandleRetainInventory(ply, savedInfo)
    end
end)

function Save_position(ply)
    RunConsoleCommand("save_position")
end

hook.Add("PlayerPostThink", "AutoSavePosition", function(ply)
    if not RARELOAD.settings.autoSaveEnabled then return end
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end

    local currentTime = CurTime()
    if currentTime - RARELOAD.lastSavedTime <= 5 then return end

    local vel = ply:GetVelocity():Length()
    if vel >= 5 then return end

    local currentPos = ply:GetPos()
    local currentWeapons = {}
    for _, weapon in pairs(ply:GetWeapons()) do
        table.insert(currentWeapons, weapon:GetClass())
    end

    local positionChanged = not ply.lastSavedPosition or not currentPos:DistToSqr(ply.lastSavedPosition) < 1
    local weaponsChanged = not ply.lastSavedWeapons or #currentWeapons ~= #ply.lastSavedWeapons

    if not positionChanged and not weaponsChanged then
        for i, weapon in ipairs(currentWeapons) do
            if weapon ~= ply.lastSavedWeapons[i] then
                weaponsChanged = true
                break
            end
        end
    end

    if not positionChanged and not weaponsChanged then return end

    Save_position(ply)
    RARELOAD.lastSavedTime = currentTime
    ply.lastSavedPosition = currentPos
    ply.lastSavedWeapons = currentWeapons
end)


-- lua/autorun/server/sv_rareload_hooks.lua

hook.Add("PostDrawOpaqueRenderables", "DrawSpawnPointFrame", function()
    if not RARELOAD.settings.debugEnabled then return end

    for _, spawnPoint in ipairs(ents.FindByClass("ent_rareload_spawnpoint")) do
        if IsValid(spawnPoint) then
            local playerPos = LocalPlayer():GetPos()
            local spawnPointPos = spawnPoint:GetPos()
            local distance = playerPos:Distance(spawnPointPos)

            if distance <= 100 then
                local pos = spawnPointPos + Vector(0, 0, 50)
                local ang = Angle(0, LocalPlayer():EyeAngles().yaw - 90, 90)

                surface.SetFont("DermaDefaultBold")
                local panelWidth = 0
                local panelHeight = 10
                local textSpacing = 2

                local offsetY = 0

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
                    RARELOAD.playerPositions[mapName][spawnPoint:GetNWString("PlayerSteamID")]

                if savedInfo then
                    local shouldDraw, text, textHeight = drawTextLine("Spawn Point", "Active")
                    if shouldDraw then
                        table.insert(linesToDraw, { text, yPos })
                        yPos = yPos + textHeight + textSpacing
                    end

                    shouldDraw, text, textHeight = drawTextLine("Position", tostring(savedInfo.pos))
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
                offsetY = -panelHeight / 2

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
