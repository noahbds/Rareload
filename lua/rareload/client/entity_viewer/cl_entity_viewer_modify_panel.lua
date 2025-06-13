local function ParsePosString(str)
    if type(str) ~= "string" then
        if type(str) == "table" and str.x ~= nil and str.y ~= nil and str.z ~= nil then
            return str
        end
        return nil
    end
    local x, y, z = string.match(str, "%[%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*%]")
    if not (x and y and z) then
        x, y, z = string.match(str, "^%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*$")
    end
    if not (x and y and z) then
        x, y, z = string.match(str, "^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
    end
    if x and y and z then
        return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end
    return nil
end

local function PosTableToString(pos)
    if type(pos) == "table" and pos.x ~= nil and pos.y ~= nil and pos.z ~= nil then
        return string.format("[%.4f %.4f %.4f]", pos.x, pos.y, pos.z)
    elseif type(pos) == "string" then
        if not string.match(pos, "^%[.*%]$") then
            local x, y, z = string.match(pos, "([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
            if x and y and z then
                return string.format("[%.4f %.4f %.4f]", tonumber(x), tonumber(y), tonumber(z))
            end
        end
        return pos
    end
    return nil
end

local function AngTableToString(ang)
    if type(ang) == "table" and ang.p and ang.y and ang.r then
        return string.format("{%.4f %.4f %.4f}", ang.p, ang.y, ang.r)
    elseif type(ang) == "string" then
        if not string.match(ang, "^{.*}$") then
            local p, y, r = string.match(ang, "([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
            if p and y and r then
                return string.format("{%.4f %.4f %.4f}", tonumber(p), tonumber(y), tonumber(r))
            end
        end
    elseif type(ang) == "table" and #ang >= 3 then
        return string.format("{%.4f %.4f %.4f}", ang[1], ang[2], ang[3])
    end
    return nil
end

function CreateModifyDataButton(actionsPanel, data, isNPC, onAction)
    local modifyBtn = CreateStyledButton(actionsPanel, "Modify Data", "icon16/pencil.png", THEME.warning, function()
        local editData = table.Copy(data)
        if editData.pos and type(editData.pos) == "table" then
            editData.pos = PosTableToString(editData.pos)
        end
        if editData.ang and type(editData.ang) == "table" then
            editData.ang = AngTableToString(editData.ang)
        end
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
        editFrame.Paint = function(self, w, h)
            draw.RoundedBox(12, 0, 0, w, h, THEME.background)
            local headerColor1 = Color(THEME.warning.r, THEME.warning.g, THEME.warning.b, 255)
            local headerColor2 = Color(THEME.warning.r * 0.8, THEME.warning.g * 0.8, THEME.warning.b * 0.8, 255)
            surface.SetDrawColor(headerColor1)
            surface.DrawRect(0, 0, w, 45)
            surface.SetDrawColor(headerColor2)
            surface.DrawRect(0, 35, w, 10)
            draw.RoundedBoxEx(12, 0, 0, w, 45, headerColor1, true, true, false, false)
            surface.SetDrawColor(255, 255, 255, 220)
            surface.SetMaterial(Material("icon16/pencil.png"))
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
            local col2 = Color(THEME.surface.r, THEME.surface.g, THEME.surface.b, 150)
            draw.RoundedBox(8, 0, 0, w, h, col1)
            surface.SetDrawColor(THEME.info.r, THEME.info.g, THEME.info.b, 180)
            surface.SetMaterial(Material("icon16/information.png"))
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
        local textEntry = vgui.Create("DTextEntry", scrollPanel)
        textEntry:Dock(TOP)
        textEntry:SetMultiline(true)
        textEntry:SetFont("Trebuchet24")
        textEntry:SetUpdateOnType(true)
        textEntry:SetDrawLanguageID(false)
        textEntry:SetTextColor(Color(220, 220, 230, 255))
        local isInteracting = false
        textEntry.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(25, 25, 35, 255))
            if self:HasFocus() then
                self:SetTextColor(Color(220, 220, 230, 255))
                derma.SkinHook("Paint", "TextEntry", self, w, h)
                return
            end
            local text = self:GetValue()
            local lines = string.Split(text, "\n")
            local lineHeight = 28
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
                            local keyword = string.match(remaining, "^(true|false|null)")
                            if keyword then
                                surface.SetFont("Trebuchet24")
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
                                if inKey then
                                    color = Color(102, 217, 239, 255)
                                else
                                    color = Color(166, 226, 46, 255)
                                end
                            elseif string.match(char, "[%d%.%-]") and not inString then
                                color = Color(253, 151, 31, 255)
                            elseif string.match(char, "[{}%[%]]") then
                                color = Color(249, 38, 114, 255)
                            elseif char == ":" then
                                color = Color(248, 248, 242, 255)
                            elseif char == "," then
                                color = Color(248, 248, 242, 255)
                            end
                            surface.SetFont("Trebuchet24")
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
        textEntry.OnCursorEntered = nil
        textEntry.OnCursorExited = nil
        textEntry.OnMousePressed = function(self, mouseCode)
        end
        textEntry.OnMouseReleased = function(self, mouseCode)
        end
        textEntry.OnGetFocus = function(self)
            self:InvalidateLayout()
        end
        textEntry.OnLoseFocus = function(self)
            self:InvalidateLayout()
        end
        local function updateSyntaxHighlighting()
            local text = textEntry:GetValue()
            local lines = string.Split(text, "\n")
            local lineHeight = 28
            local lineCount = #lines
            local requiredHeight = math.max(lineCount * lineHeight + 40, 400)
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
        lineNumbers.Paint = function(self, w, h)
            local text = textEntry:GetValue()
            local lines = string.Split(text, "\n")
            for i = 1, #lines do
                local y = (i - 1) * 28 + 8
                if y < h then
                    draw.SimpleText(tostring(i), "Trebuchet18", w - 8, y,
                        Color(120, 140, 160, 255), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
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
                    surface.SetMaterial(Material("icon16/tick.png"))
                    surface.DrawTexturedRect(8, 10, 16, 16)
                end
                return true, result
            else
                local errorMsg = tostring(result or "Unknown error")
                if string.len(errorMsg) > 60 then
                    errorMsg = string.sub(errorMsg, 1, 60) .. "..."
                end
                statusLabel:SetText("✗ " .. errorMsg)
                statusLabel:SetTextColor(THEME.error)
                statusPanel.Paint = function(self, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, Color(THEME.error.r, THEME.error.g, THEME.error.b, 40))
                    surface.SetDrawColor(THEME.error.r, THEME.error.g, THEME.error.b, 180)
                    surface.SetMaterial(Material("icon16/exclamation.png"))
                    surface.DrawTexturedRect(8, 10, 16, 16)
                end
                return false, nil
            end
        end
        local validationTimer = nil
        textEntry.OnValueChange = function(self)
            if validationTimer then timer.Remove(validationTimer) end
            validationTimer = timer.Simple(0.3, function()
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
                if icon then
                    surface.SetDrawColor(255, 255, 255, 230)
                    surface.SetMaterial(Material(icon))
                    surface.DrawTexturedRect(12, h / 2 - 8, 16, 16)
                end
                draw.SimpleText(text, "RareloadText", icon and 35 or w / 2, h / 2,
                    Color(255, 255, 255, 240), icon and TEXT_ALIGN_LEFT or TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            btn.DoClick = function()
                surface.PlaySound("ui/buttonclickrelease.wav")
                onClick()
            end
            return btn
        end
        local formatBtn = CreateModernButton(buttonPanel, "Format", "icon16/page_white_code.png",
            Color(100, 120, 255, 255), function()
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
        local resetBtn = CreateModernButton(buttonPanel, "Reset", "icon16/arrow_undo.png",
            Color(120, 120, 120, 255), function()
                textEntry:SetText(formattedJson)
                updateSyntaxHighlighting()
                validateJSON()
            end)
        resetBtn:Dock(LEFT)
        resetBtn:SetWide(90)
        resetBtn:DockMargin(0, 8, 5, 8)
        local cancelBtn = CreateModernButton(buttonPanel, "Cancel", "icon16/cross.png",
            Color(140, 140, 140, 255), function()
                editFrame:Close()
            end)
        cancelBtn:Dock(RIGHT)
        cancelBtn:SetWide(90)
        cancelBtn:DockMargin(5, 8, 10, 8)
        local saveBtn = CreateModernButton(buttonPanel, "Save Changes", "icon16/disk.png",
            THEME.success, function()
                local valid, newData = validateJSON()
                if not valid then
                    ShowNotification("Cannot save invalid JSON!", NOTIFY_ERROR)
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
                                            if newData.pos and type(newData.pos) == "table" then
                                                newData.pos = PosTableToString(newData.pos)
                                            end
                                            if newData.ang and type(newData.ang) == "table" then
                                                newData.ang = AngTableToString(newData.ang)
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

include("rareload/utils/vector_serialization.lua")
local ParsePosString = RARELOAD.ParsePosString
local ParseAngString = RARELOAD.ParseAngString
local PosTableToString = RARELOAD.PosTableToString
local AngTableToString = RARELOAD.AngTableToString
