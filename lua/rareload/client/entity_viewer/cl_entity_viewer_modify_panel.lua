include("rareload/utils/vector_serialization.lua")

local draw, surface, string, math, util, file, net, timer, IsValid, pairs, ipairs, tostring =
    draw, surface, string, math, util, file, net, timer, IsValid, pairs, ipairs, tostring

local MAT_PENCIL                                                                            = Material(
    "icon16/pencil.png")
local MAT_INFO                                                                              = Material(
    "icon16/information.png")
local MAT_TICK                                                                              = Material("icon16/tick.png")
local MAT_EXCLAIM                                                                           = Material(
    "icon16/exclamation.png")
local MAT_PAGE_CODE                                                                         = Material(
    "icon16/page_white_code.png")
local MAT_UNDO                                                                              = Material(
    "icon16/arrow_undo.png")
local MAT_CROSS                                                                             = Material(
    "icon16/cross.png")
local MAT_DISK                                                                              = Material("icon16/disk.png")

local KEYWORD_PATTERN                                                                       = "^(true|false|null)"
local LHEIGHT                                                                               = 28

local ParsePosString                                                                        = RARELOAD.ParsePosString
local PosTableToString                                                                      = RARELOAD.PosTableToString
local AngTableToString                                                                      = RARELOAD.AngTableToString

function CreateModifyDataButton(actionsPanel, data, isNPC, onAction)
    local modifyBtn = CreateStyledButton(actionsPanel, "Modify Data", "icon16/pencil.png", THEME.warning, function()
        local editData = table.Copy(data)
        if editData.pos and type(editData.pos) == "table" then
            editData.pos = PosTableToString(editData.pos)
        end
        if editData.ang and type(editData.ang) == "table" then
            editData.ang = AngTableToString(editData.ang)
        end

        ---@class DFrame
        local editFrame = vgui.Create("DFrame")
        editFrame:SetSize(1000, 800)
        editFrame:Center()
        editFrame:SetTitle("")
        editFrame:MakePopup()
        editFrame:SetBackgroundBlur(true)
        editFrame:SetDeleteOnClose(true)
        editFrame:SetSizable(true)
        editFrame:SetMinWidth(800)
        editFrame:SetMinHeight(600)

        local headerColor1 = Color(THEME.warning.r, THEME.warning.g, THEME.warning.b, 255)
        local headerColor2 = Color(
            math.floor(THEME.warning.r * 0.8),
            math.floor(THEME.warning.g * 0.8),
            math.floor(THEME.warning.b * 0.8),
            255
        )

        editFrame.Paint = function(self, w, h)
            draw.RoundedBox(12, 0, 0, w, h, THEME.background)
            surface.SetDrawColor(headerColor1)
            surface.DrawRect(0, 0, w, 45)
            surface.SetDrawColor(headerColor2)
            surface.DrawRect(0, 35, w, 10)
            draw.RoundedBoxEx(12, 0, 0, w, 45, headerColor1, true, true, false, false)

            surface.SetDrawColor(255, 255, 255, 220)
            surface.SetMaterial(MAT_PENCIL)
            surface.DrawTexturedRect(20, 14, 16, 16)

            draw.SimpleText("Entity Data Editor", "RareloadHeading", 45, 23, THEME.textPrimary, TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)

            surface.SetDrawColor(THEME.border.r, THEME.border.g, THEME.border.b, 100)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        local contentContainer = vgui.Create("DPanel", editFrame)
        contentContainer:Dock(FILL)
        contentContainer:DockMargin(15, 55, 15, 15)
        contentContainer.Paint = function() end

        local instructionPanel = vgui.Create("DPanel", contentContainer)
        instructionPanel:Dock(TOP)
        instructionPanel:SetTall(70)
        instructionPanel:DockMargin(0, 0, 0, 10)
        instructionPanel.Paint = function(self, w, h)
            local col1 = Color(THEME.surfaceVariant.r, THEME.surfaceVariant.g, THEME.surfaceVariant.b, 100)
            draw.RoundedBox(8, 0, 0, w, h, col1)

            surface.SetDrawColor(THEME.info.r, THEME.info.g, THEME.info.b, 180)
            surface.SetMaterial(MAT_INFO)
            surface.DrawTexturedRect(15, 15, 16, 16)
        end

        local instructionLabel = vgui.Create("DLabel", instructionPanel)
        instructionLabel:SetText(
            "Edit the JSON data below. Changes are validated in real-time.\nUse Ctrl+A to select all, Ctrl+Z to undo.")
        instructionLabel:SetFont("RareloadText")
        instructionLabel:SetTextColor(THEME.textSecondary)
        instructionLabel:Dock(FILL)
        instructionLabel:DockMargin(40, 10, 15, 10)
        instructionLabel:SetContentAlignment(7)

        local editorContainer = vgui.Create("DPanel", contentContainer)
        editorContainer:Dock(FILL)
        editorContainer:DockMargin(0, 0, 0, 80)
        editorContainer.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(30, 30, 40, 255))
            surface.SetDrawColor(THEME.border.r, THEME.border.g, THEME.border.b, 150)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
            draw.RoundedBoxEx(8, 0, 0, 60, h, Color(20, 20, 30, 255), true, false, true, false)
            surface.SetDrawColor(THEME.border.r, THEME.border.g, THEME.border.b, 100)
            surface.DrawRect(60, 0, 1, h)
        end

        local scrollPanel = vgui.Create("DScrollPanel", editorContainer)
        scrollPanel:Dock(FILL)
        scrollPanel:DockMargin(65, 8, 8, 8)
        local scrollbar = scrollPanel:GetVBar()
        scrollbar:SetWide(12)
        scrollbar.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(20, 20, 30, 200))
        end
        scrollbar.btnGrip.Paint = function(self, w, h)
            local color = self:IsHovered() and Color(120, 120, 140, 255) or Color(80, 80, 100, 255)
            draw.RoundedBox(6, 2, 0, w - 4, h, color)
        end
        scrollbar.btnUp.Paint = function() end
        scrollbar.btnDown.Paint = function() end

        ---@class DTextEntry
        local textEntry = vgui.Create("DTextEntry", scrollPanel)
        textEntry:Dock(TOP)
        textEntry:SetMultiline(true)
        textEntry:SetFont("Trebuchet24")
        textEntry:SetUpdateOnType(true)
        textEntry:SetDrawLanguageID(false)
        textEntry:SetTextColor(Color(220, 220, 230, 255))

        textEntry.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(25, 25, 35, 255))

            if self:HasFocus() then
                self:SetTextColor(Color(220, 220, 230, 255))
                derma.SkinHook("Paint", "TextEntry", self, w, h)
                return
            end

            local text = self:GetValue()
            local lines = string.Split(text, "\n")
            local lineHeight = LHEIGHT

            surface.SetFont("Trebuchet24")

            for i, line in ipairs(lines) do
                local y = (i - 1) * lineHeight + 5
                if y < h + lineHeight and y > -lineHeight then
                    local x = 8
                    local inString = false
                    local inKey = false
                    local stringChar = nil
                    local j = 1

                    while j <= #line do
                        local char = string.sub(line, j, j)
                        local color = Color(220, 220, 230, 255)
                        local skipChar = false

                        if (char == '"' or char == "'") and (j == 1 or string.sub(line, j - 1, j - 1) ~= "\\") then
                            if not inString then
                                inString = true
                                stringChar = char
                                local restOfLine = string.sub(line, j)
                                if string.find(restOfLine, "^[\"'][^\"']*[\"']%s*:") then
                                    inKey = true
                                end
                            elseif char == stringChar then
                                inString = false
                                inKey = false
                                stringChar = nil
                            end
                        end

                        if not inString then
                            local remaining = string.sub(line, j)
                            local keyword = string.match(remaining, KEYWORD_PATTERN)
                            if keyword then
                                surface.SetTextColor(174, 129, 255, 255)
                                surface.SetTextPos(x, y)
                                surface.DrawText(keyword)
                                x = x + surface.GetTextSize(keyword)
                                j = j + #keyword - 1
                                skipChar = true
                            end
                        end

                        if not skipChar then
                            if inString then
                                color = inKey and Color(102, 217, 239, 255) or Color(166, 226, 46, 255)
                            elseif string.match(char, "[%d%.%-]") then
                                color = Color(253, 151, 31, 255)
                            elseif string.match(char, "[{}%[%]]") then
                                color = Color(249, 38, 114, 255)
                            elseif char == ":" or char == "," then
                                color = Color(248, 248, 242, 255)
                            end

                            local charWidth = surface.GetTextSize(char)
                            surface.SetTextColor(color)
                            surface.SetTextPos(x, y)
                            surface.DrawText(char)
                            x = x + charWidth
                        end

                        j = j + 1
                    end
                end
            end
        end

        local function updateSyntaxHighlighting()
            local text = textEntry:GetValue()
            local lines = string.Split(text, "\n")
            local lineCount = #lines
            CurrentLineCount = lineCount

            local requiredHeight = math.max(lineCount * LHEIGHT + 40, 400)
            textEntry:SetTall(requiredHeight)

            if IsValid(lineNumbers) then
                lineNumbers:SetSize(55, editorContainer:GetTall() - 16)
            end
        end

        local function formatJSON(jsonTable, indent)
            indent = indent or 0
            local indentStr = string.rep("  ", indent)
            local nextIndentStr = string.rep("  ", indent + 1)
            if type(jsonTable) == "table" then
                local isArray = true
                local count = 0
                for k, v in pairs(jsonTable) do
                    count = count + 1
                    if type(k) ~= "number" or k ~= count then
                        isArray = false
                        break
                    end
                end
                if isArray and count > 0 then
                    local result = "[\n"
                    for i = 1, count do
                        result = result .. nextIndentStr .. formatJSON(jsonTable[i], indent + 1)
                        if i < count then
                            result = result .. ","
                        end
                        result = result .. "\n"
                    end
                    result = result .. indentStr .. "]"
                    return result
                else
                    local result = "{\n"
                    local keys = {}
                    for k, _ in pairs(jsonTable) do
                        table.insert(keys, k)
                    end
                    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
                    for i, k in ipairs(keys) do
                        local v = jsonTable[k]
                        result = result .. nextIndentStr .. '"' .. tostring(k) .. '": ' .. formatJSON(v, indent + 1)
                        if i < #keys then
                            result = result .. ","
                        end
                        result = result .. "\n"
                    end
                    result = result .. indentStr .. "}"
                    return result
                end
            elseif type(jsonTable) == "string" then
                return '"' .. tostring(jsonTable) .. '"'
            elseif type(jsonTable) == "number" then
                return tostring(jsonTable)
            elseif type(jsonTable) == "boolean" then
                return tostring(jsonTable)
            else
                return "null"
            end
        end

        local formattedJson = formatJSON(editData)
        textEntry:SetText(formattedJson)
        updateSyntaxHighlighting()

        local lineNumbers = vgui.Create("DPanel", editorContainer)
        lineNumbers:SetPos(8, 8)
        lineNumbers:SetSize(55, editorContainer:GetTall() - 16)
        lineNumbers:SetMouseInputEnabled(false)

        CurrentLineCount = 0
        lineNumbers.Paint = function(self, w, h)
            for i = 1, CurrentLineCount do
                local y = (i - 1) * LHEIGHT + 8
                if y < h then
                    draw.SimpleText(tostring(i), "Trebuchet18", w - 8, y, Color(120, 140, 160, 255), TEXT_ALIGN_RIGHT,
                        TEXT_ALIGN_TOP)
                else
                    break
                end
            end
        end

        local statusContainer = vgui.Create("DPanel", contentContainer)
        statusContainer:Dock(BOTTOM)
        statusContainer:SetTall(35)
        statusContainer:DockMargin(0, 10, 0, 10)
        statusContainer.Paint = function() end

        local statusPanel = vgui.Create("DPanel", statusContainer)
        statusPanel:Dock(FILL)
        statusPanel:DockMargin(0, 0, 0, 0)

        local statusLabel = vgui.Create("DLabel", statusPanel)
        statusLabel:Dock(FILL)
        statusLabel:SetFont("RareloadText")
        statusLabel:SetText("✓ Valid JSON - Ready to save")
        statusLabel:SetTextColor(THEME.success)
        statusLabel:SetContentAlignment(4)
        statusLabel:DockMargin(15, 0, 0, 0)

        local function validateJSON()
            local jsonText = textEntry:GetValue()
            local ok, result = pcall(util.JSONToTable, jsonText)

            if ok and istable(result) then
                statusLabel:SetText("✓ Valid JSON - Ready to save")
                statusLabel:SetTextColor(THEME.success)
                statusPanel.Paint = function(self, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, Color(THEME.success.r, THEME.success.g, THEME.success.b, 40))
                    surface.SetDrawColor(THEME.success.r, THEME.success.g, THEME.success.b, 180)
                    surface.SetMaterial(MAT_TICK)
                    surface.DrawTexturedRect(8, 10, 16, 16)
                end
                return true, result
            else
                local errorMsg = "Invalid JSON"
                statusLabel:SetText("✗ " .. errorMsg)
                statusLabel:SetTextColor(THEME.error)
                statusPanel.Paint = function(self, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, Color(THEME.error.r, THEME.error.g, THEME.error.b, 40))
                    surface.SetDrawColor(THEME.error.r, THEME.error.g, THEME.error.b, 180)
                    surface.SetMaterial(MAT_EXCLAIM)
                    surface.DrawTexturedRect(8, 10, 16, 16)
                end
                return false, nil
            end
        end

        local debounceName = "Rareload_JSONValidate_" .. tostring(textEntry)
        textEntry.OnValueChange = function(self)
            timer.Remove(debounceName)
            timer.Create(debounceName, 0.25, 1, function()
                if not IsValid(self) then return end
                validateJSON()
                updateSyntaxHighlighting()
            end)
        end

        textEntry.OnGetFocus = function(self)
            self:InvalidateLayout()
        end
        textEntry.OnLoseFocus = function(self)
            self:InvalidateLayout()
        end

        local buttonPanel = vgui.Create("DPanel", contentContainer)
        buttonPanel:Dock(BOTTOM)
        buttonPanel:SetTall(50)
        buttonPanel:DockMargin(0, 0, 0, 0)
        buttonPanel.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h,
                Color(THEME.backgroundDark.r, THEME.backgroundDark.g, THEME.backgroundDark.b, 100))
        end

        local function CreateModernButton(parent, text, icon, color, onClick)
            local btn = vgui.Create("DButton", parent)
            btn:SetText("")
            btn:SetFont("RareloadText")

            local iconMat = icon
            if type(iconMat) == "string" then
                iconMat = Material(iconMat)
            end

            btn.Paint = function(self, w, h)
                local baseColor = color
                local btnColor = baseColor
                if self:IsHovered() then
                    btnColor = Color(baseColor.r * 1.1, baseColor.g * 1.1, baseColor.b * 1.1, baseColor.a)
                end
                if self:IsDown() then
                    btnColor = Color(baseColor.r * 0.9, baseColor.g * 0.9, baseColor.b * 0.9, baseColor.a)
                end

                draw.RoundedBox(8, 0, 0, w, h, btnColor)

                if iconMat then
                    surface.SetDrawColor(255, 255, 255, 230)
                    surface.SetMaterial(iconMat)
                    surface.DrawTexturedRect(12, h / 2 - 8, 16, 16)
                end

                draw.SimpleText(text, "RareloadText", iconMat and 35 or w / 2, h / 2, Color(255, 255, 255, 240),
                    iconMat and TEXT_ALIGN_LEFT or TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            btn.DoClick = function()
                surface.PlaySound("ui/buttonclickrelease.wav")
                onClick()
            end

            return btn
        end

        local formatBtn = CreateModernButton(buttonPanel, "Format", MAT_PAGE_CODE, Color(100, 120, 255, 255), function()
            local valid, parsedData = validateJSON()
            if valid then
                local beautified = formatJSON(parsedData)
                textEntry:SetText(beautified)
                updateSyntaxHighlighting()
                ShowNotification("JSON formatted successfully!", NOTIFY_GENERIC)
            else
                ShowNotification("Cannot format invalid JSON!", NOTIFY_ERROR)
            end
        end)
        formatBtn:Dock(LEFT)
        formatBtn:SetWide(100)
        formatBtn:DockMargin(10, 8, 5, 8)

        local resetBtn = CreateModernButton(buttonPanel, "Reset", MAT_UNDO, Color(120, 120, 120, 255), function()
            textEntry:SetText(formattedJson)
            updateSyntaxHighlighting()
            validateJSON()
        end)
        resetBtn:Dock(LEFT)
        resetBtn:SetWide(90)
        resetBtn:DockMargin(0, 8, 5, 8)

        local cancelBtn = CreateModernButton(buttonPanel, "Cancel", MAT_CROSS, Color(140, 140, 140, 255), function()
            editFrame:Close()
        end)
        cancelBtn:Dock(RIGHT)
        cancelBtn:SetWide(90)
        cancelBtn:DockMargin(5, 8, 10, 8)

        local saveBtn = CreateModernButton(buttonPanel, "Save Changes", MAT_DISK, THEME.success, function()
            local valid, newData = validateJSON()
            if not valid then
                ShowNotification("Cannot save invalid JSON!", NOTIFY_ERROR)
                surface.PlaySound("buttons/button10.wav")
                return
            end

            if not newData or not istable(newData) then
                ShowNotification("Invalid data format!", NOTIFY_ERROR)
                surface.PlaySound("buttons/button10.wav")
                return
            end

            if not newData.class then
                ShowNotification("Entity class is required!", NOTIFY_ERROR)
                return
            end
            if not newData.pos or (type(newData.pos) == "string" and not ParsePosString(newData.pos)) then
                ShowNotification("Entity position (pos) is missing or invalid!", NOTIFY_ERROR)
                return
            end
            local loadingOverlay = vgui.Create("DPanel", editFrame)
            loadingOverlay:SetSize(editFrame:GetSize())
            loadingOverlay:SetPos(0, 0)
            local rotation = 0
            loadingOverlay.Paint = function(self, w, h)
                draw.RoundedBox(12, 0, 0, w, h, Color(0, 0, 0, 180))
                rotation = (rotation + FrameTime() * 360) % 360
                local centerX, centerY = w / 2, h / 2
                surface.SetDrawColor(255, 255, 255, 200)
                for i = 0, 7 do
                    local angle = rotation + (i * 45)
                    local x = centerX + math.cos(math.rad(angle)) * 20
                    local y = centerY + math.sin(math.rad(angle)) * 20
                    local alpha = 255 - (i * 30)
                    surface.SetDrawColor(255, 255, 255, alpha)
                    surface.DrawRect(x - 2, y - 2, 4, 4)
                end
                draw.SimpleText("Saving changes...", "RareloadSubheading", w / 2, h / 2 + 40,
                    Color(255, 255, 255, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            timer.Simple(0.2, function()
                local success = false
                local mapName = game.GetMap()
                local filePath = "rareload/player_positions_" .. mapName .. ".json"
                if file.Exists(filePath, "DATA") then
                    local fileOk, rawData = pcall(util.JSONToTable, file.Read(filePath, "DATA"))
                    if fileOk and rawData and rawData[mapName] then
                        for playerId, playerData in pairs(rawData[mapName]) do
                            local arr = isNPC and playerData.npcs or playerData.entities
                            if arr then
                                for i, ent in ipairs(arr) do
                                    local entCopy = table.Copy(ent)
                                    local dataCopy = table.Copy(data)
                                    if type(entCopy.pos) == "string" then
                                        entCopy.pos = ParsePosString(entCopy.pos)
                                    end
                                    if type(dataCopy.pos) == "string" then
                                        dataCopy.pos = ParsePosString(dataCopy.pos)
                                    end
                                    if ent.class == data.class and entCopy.pos and dataCopy.pos and
                                        math.abs(entCopy.pos.x - dataCopy.pos.x) < 0.1 and
                                        math.abs(entCopy.pos.y - dataCopy.pos.y) < 0.1 and
                                        math.abs(entCopy.pos.z - dataCopy.pos.z) < 0.1 then
                                        if newData.pos then
                                            newData.pos = RARELOAD.DataUtils.FormatPositionForJSON(newData.pos, 4)
                                        end
                                        if newData.ang then
                                            newData.ang = RARELOAD.DataUtils.FormatAngleForJSON(newData.ang, 4)
                                        end
                                        arr[i] = newData
                                        success = true
                                        break
                                    end
                                end
                            end
                            if success then break end
                        end
                        if success then
                            local writeOk, writeError = pcall(file.Write, filePath, util.TableToJSON(rawData, true))
                            if writeOk then
                                net.Start("RareloadReloadData")
                                net.SendToServer()
                                ShowNotification("Entity data updated successfully!", NOTIFY_GENERIC)
                                if onAction then onAction("modify_data", newData) end
                                editFrame:Close()
                            else
                                ShowNotification("Failed to write file: " .. (writeError or "Unknown error"),
                                    NOTIFY_ERROR)
                            end
                        else
                            ShowNotification("Entity not found in save file!", NOTIFY_ERROR)
                        end
                    else
                        ShowNotification("Failed to read save file data!", NOTIFY_ERROR)
                    end
                else
                    ShowNotification("Save file does not exist!", NOTIFY_ERROR)
                end
                if IsValid(loadingOverlay) then
                    loadingOverlay:Remove()
                end
            end)
        end)
        saveBtn:Dock(FILL)
        saveBtn:DockMargin(5, 8, 5, 8)

        validateJSON()
        timer.Simple(0.1, function()
            if IsValid(textEntry) then
                textEntry:RequestFocus()
                updateSyntaxHighlighting()
            end
        end)
    end)
    modifyBtn:Dock(LEFT)
    modifyBtn:DockMargin(0, 4, 4, 4)
    return modifyBtn
end
