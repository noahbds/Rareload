local draw, surface, string, math, util, file, net, timer, IsValid, pairs, tostring =
    draw, surface, string, math, util, file, net, timer, IsValid, pairs, tostring

local MAT_PENCIL = Material("icon16/pencil.png")

local function CreateModernButton(parent, text, icon, color, onClick)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn:SetFont("RareloadText")

    local iconMat = type(icon) == "string" and Material(icon) or icon

    btn.Paint = function(self, w, h)
        local btnColor = color
        if self:IsHovered() then
            btnColor = Color(
                math.Clamp(color.r * 1.1, 0, 255),
                math.Clamp(color.g * 1.1, 0, 255),
                math.Clamp(color.b * 1.1, 0, 255),
                color.a)
        end
        if self:IsDown() then
            btnColor = Color(
                math.Clamp(color.r * 0.9, 0, 255),
                math.Clamp(color.g * 0.9, 0, 255),
                math.Clamp(color.b * 0.9, 0, 255),
                color.a)
        end

        draw.RoundedBox(8, 0, 0, w, h, btnColor)

        if iconMat then
            surface.SetDrawColor(255, 255, 255, 230)
            surface.SetMaterial(iconMat)
            surface.DrawTexturedRect(12, h / 2 - 8, 16, 16)
        end

        draw.SimpleText(text, "RareloadText",
            iconMat and 35 or w / 2, h / 2,
            Color(255, 255, 255, 240),
            iconMat and TEXT_ALIGN_LEFT or TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    btn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        onClick()
    end

    return btn
end

function CreateModifyDataButton(actionsPanel, data, isNPC, onAction)
    local modifyBtn = CreateModernButton(actionsPanel, "Modify Data", MAT_PENCIL, THEME.warning, function()
        local editFrame = vgui.Create("DFrame")
        editFrame:SetSize(1000, 800)
        editFrame:Center()
        editFrame:SetTitle("")
        editFrame:MakePopup()
        editFrame:SetBackgroundBlur(true)
        editFrame:SetSizable(true)
        editFrame:SetMinWidth(800)
        editFrame:SetMinHeight(600)

        editFrame.Paint = function(self, w, h)
            draw.RoundedBox(12, 0, 0, w, h, THEME.background)
            draw.RoundedBoxEx(12, 0, 0, w, 45,
                Color(THEME.warning.r, THEME.warning.g, THEME.warning.b, 255),
                true, true, false, false)

            surface.SetDrawColor(255, 255, 255, 220)
            surface.SetMaterial(MAT_PENCIL)
            surface.DrawTexturedRect(20, 14, 16, 16)

            draw.SimpleText("Entity Data Editor", "RareloadHeading", 45, 23,
                THEME.textPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            surface.SetDrawColor(THEME.border.r, THEME.border.g, THEME.border.b, 100)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        local contentContainer = vgui.Create("DPanel", editFrame)
        contentContainer:Dock(FILL)
        contentContainer:DockMargin(15, 55, 15, 15)
        contentContainer.Paint = function() end

        if RARELOAD.JSONEditor and RARELOAD.JSONEditor.Create then
            RARELOAD.JSONEditor.Create(contentContainer, data, isNPC, function(newData)
                if not newData.class then
                    ShowNotification("Entity class is required!", NOTIFY_ERROR)
                    return
                end
                if not newData.pos then
                    ShowNotification("Entity position (pos) is missing!", NOTIFY_ERROR)
                    return
                end

                local mapName  = game.GetMap()
                local filePath = "rareload/player_positions_" .. mapName .. ".json"

                if not file.Exists(filePath, "DATA") then
                    ShowNotification("Save file does not exist!", NOTIFY_ERROR)
                    return
                end

                local fileOk, rawData = pcall(util.JSONToTable, file.Read(filePath, "DATA"))
                if not fileOk or not rawData or not rawData[mapName] then
                    ShowNotification("Failed to read save file!", NOTIFY_ERROR)
                    return
                end

                local success = false

                for _, playerData in pairs(rawData[mapName]) do
                    local container = isNPC and playerData.npcs or playerData.entities
                    local entityMap = container

                    if container and container.__duplicator
                        and container.__duplicator.payload
                        and container.__duplicator.payload.Entities then
                        entityMap = container.__duplicator.payload.Entities
                    end

                    if entityMap then
                        for k, ent in pairs(entityMap) do
                            if k == "__duplicator" then continue end

                            local isMatch = false
                            if data.__originalKey and tostring(k) == tostring(data.__originalKey) then
                                isMatch = true
                            else
                                local eClass = ent.Class or ent.class
                                local ePos   = ent.Pos or ent.pos
                                local dPos   = data.pos

                                if eClass == data.class and ePos and dPos then
                                    local ep = RARELOAD.DataUtils.ToPositionTable(ePos)
                                    local dp = RARELOAD.DataUtils.ToPositionTable(dPos)
                                    if ep and dp
                                        and math.abs(ep.x - dp.x) < 0.1
                                        and math.abs(ep.y - dp.y) < 0.1
                                        and math.abs(ep.z - dp.z) < 0.1 then
                                        isMatch = true
                                    end
                                end
                            end

                            if isMatch then
                                local function UpdateField(target, keyLower, keyUpper, value)
                                    if target[keyUpper] ~= nil then
                                        target[keyUpper] = value
                                    else
                                        target[keyLower] = value
                                    end
                                end

                                if newData.pos then
                                    UpdateField(entityMap[k], "pos", "Pos",
                                        RARELOAD.DataUtils.ConvertToPositionObject(newData.pos))
                                end
                                if newData.ang then
                                    UpdateField(entityMap[k], "ang", "Angle",
                                        RARELOAD.DataUtils.ToAngleTable(newData.ang))
                                end
                                if newData.health then UpdateField(entityMap[k], "health", "CurHealth", newData.health) end
                                if newData.skin then UpdateField(entityMap[k], "skin", "Skin", newData.skin) end
                                if newData.model then UpdateField(entityMap[k], "model", "Model", newData.model) end

                                success = true
                                break
                            end
                        end
                    end
                    if success then break end
                end

                if success then
                    local writeOk = pcall(file.Write, filePath, util.TableToJSON(rawData, true))
                    if writeOk then
                        net.Start("RareloadReloadData")
                        net.SendToServer()
                        ShowNotification("Entity updated successfully!", NOTIFY_GENERIC)
                        if onAction then onAction("modify_data", newData) end
                        editFrame:Close()
                    else
                        ShowNotification("Failed to write save file!", NOTIFY_ERROR)
                    end
                else
                    ShowNotification("Entity not found in save file!", NOTIFY_ERROR)
                end
            end)
        else
            local errLbl = vgui.Create("DLabel", contentContainer)
            errLbl:Dock(FILL)
            errLbl:SetText("JSON Editor component is missing!")
            errLbl:SetFont("RareloadHeading")
            errLbl:SetTextColor(THEME.error)
            errLbl:SetContentAlignment(5)
        end
    end)

    modifyBtn:Dock(LEFT)
    modifyBtn:DockMargin(0, 4, 4, 4)
    return modifyBtn
end
