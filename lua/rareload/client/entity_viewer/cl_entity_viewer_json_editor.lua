RARELOAD = RARELOAD or {}
RARELOAD.JSONEditor = RARELOAD.JSONEditor or {}

surface.CreateFont("RareloadEditor", {
    font = "Courier New",
    size = 20,
    weight = 400,
    antialias = true,
    additive = false
})

surface.CreateFont("RareloadEditorSmall", {
    font = "Arial",
    size = 20,
    weight = 400,
    antialias = true,
    additive = false
})

local SYNTAX_COLORS = {
    string_key = Color(102, 217, 239),
    string_value = Color(166, 226, 46),
    number = Color(253, 151, 31),
    vector = Color(0, 255, 128),
    angle = Color(255, 153, 0),
    boolean = Color(174, 129, 255),
    bracket = Color(249, 38, 114),
    punctuation = Color(248, 248, 242),
    background = Color(30, 30, 40),
    selection = Color(70, 130, 180, 80),
    line_number = Color(120, 140, 160),
    cursor = Color(255, 255, 255),
    error = Color(255, 100, 100),
    warning = Color(255, 200, 100)
}

local function TokenizeJSON(text)
    local tokens = {}
    local pos = 1
    local len = #text

    while pos <= len do
        local char = string.sub(text, pos, pos)

        if string.match(char, "%s") then
            pos = pos + 1
        elseif char == "[" then
            local start = pos
            local potentialVector = ""
            local endPos = start

            while endPos <= len and string.sub(text, endPos, endPos) ~= "]" do
                endPos = endPos + 1
            end

            if endPos <= len then
                potentialVector = string.sub(text, start, endPos)
                if ParsePosString and ParsePosString(potentialVector) then
                    table.insert(tokens, {
                        type = "vector",
                        content = potentialVector,
                        start = start,
                        stop = endPos
                    })
                    pos = endPos + 1
                else
                    table.insert(tokens, {
                        type = "bracket",
                        content = char,
                        start = pos,
                        stop = pos
                    })
                    pos = pos + 1
                end
            else
                table.insert(tokens, {
                    type = "bracket",
                    content = char,
                    start = pos,
                    stop = pos
                })
                pos = pos + 1
            end
        elseif char == "{" then
            local start = pos
            local potentialAngle = ""
            local endPos = start

            while endPos <= len and string.sub(text, endPos, endPos) ~= "}" do
                endPos = endPos + 1
            end

            if endPos <= len then
                potentialAngle = string.sub(text, start, endPos)
                if ParseAngString and ParseAngString(potentialAngle) then
                    table.insert(tokens, {
                        type = "angle",
                        content = potentialAngle,
                        start = start,
                        stop = endPos
                    })
                    pos = endPos + 1
                else
                    table.insert(tokens, {
                        type = "bracket",
                        content = char,
                        start = pos,
                        stop = pos
                    })
                    pos = pos + 1
                end
            else
                table.insert(tokens, {
                    type = "bracket",
                    content = char,
                    start = pos,
                    stop = pos
                })
                pos = pos + 1
            end
        elseif char == '"' or char == "'" then
            local start = pos
            local quote = char
            pos = pos + 1

            while pos <= len do
                local c = string.sub(text, pos, pos)
                if c == quote and string.sub(text, pos - 1, pos - 1) ~= "\\" then
                    pos = pos + 1
                    break
                end
                pos = pos + 1
            end

            local content = string.sub(text, start, pos - 1)
            local isKey = false

            local nextNonSpace = pos
            while nextNonSpace <= len and string.match(string.sub(text, nextNonSpace, nextNonSpace), "%s") do
                nextNonSpace = nextNonSpace + 1
            end
            if nextNonSpace <= len and string.sub(text, nextNonSpace, nextNonSpace) == ":" then
                isKey = true
            end

            table.insert(tokens, {
                type = isKey and "string_key" or "string_value",
                content = content,
                start = start,
                stop = pos - 1
            })
        elseif string.match(char, "[%d%-]") then
            local start = pos
            while pos <= len and string.match(string.sub(text, pos, pos), "[%d%.%-]") do
                pos = pos + 1
            end

            table.insert(tokens, {
                type = "number",
                content = string.sub(text, start, pos - 1),
                start = start,
                stop = pos - 1
            })
        elseif string.match(char, "%a") then
            local start = pos
            while pos <= len and string.match(string.sub(text, pos, pos), "%w") do
                pos = pos + 1
            end

            local word = string.sub(text, start, pos - 1)
            if word == "true" or word == "false" or word == "null" then
                table.insert(tokens, {
                    type = "boolean",
                    content = word,
                    start = start,
                    stop = pos - 1
                })
            else
                pos = start + 1
            end
        elseif string.match(char, "[}%]]") then
            table.insert(tokens, {
                type = "bracket",
                content = char,
                start = pos,
                stop = pos
            })
            pos = pos + 1
        elseif string.match(char, "[,:;]") then
            table.insert(tokens, {
                type = "punctuation",
                content = char,
                start = pos,
                stop = pos
            })
            pos = pos + 1
        else
            pos = pos + 1
        end
    end

    return tokens
end

local function FormatJSON(data, indent)
    indent = indent or 0
    local indentStr = string.rep("  ", indent)
    local nextIndentStr = string.rep("  ", indent + 1)

    if type(data) == "table" then
        local isArray = true
        local count = 0

        for k, v in pairs(data) do
            count = count + 1
            if type(k) ~= "number" or k ~= count then
                isArray = false
                break
            end
        end

        if isArray and count > 0 then
            local result = "[\n"
            for i = 1, count do
                result = result .. nextIndentStr .. FormatJSON(data[i], indent + 1)
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
            for k, _ in pairs(data) do
                table.insert(keys, k)
            end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

            for i, k in ipairs(keys) do
                local v = data[k]
                result = result .. nextIndentStr .. '"' .. tostring(k) .. '": ' .. FormatJSON(v, indent + 1)
                if i < #keys then
                    result = result .. ","
                end
                result = result .. "\n"
            end
            result = result .. indentStr .. "}"
            return result
        end
    elseif type(data) == "string" then
        return '"' .. tostring(data) .. '"'
    elseif type(data) == "number" then
        return tostring(data)
    elseif type(data) == "boolean" then
        return tostring(data)
    else
        return "null"
    end
end

include("rareload/utils/vector_serialization.lua")
local ParsePosString = RARELOAD.ParsePosString
local ParseAngString = RARELOAD.ParseAngString
local PosTableToString = RARELOAD.PosTableToString
local AngTableToString = RARELOAD.AngTableToString

function RARELOAD.JSONEditor.Create(parent, data, isNPC, onSave)
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(FILL)
    panel.Paint = function() end

    if data.pos then
        if type(data.pos) == "table" then
            if data.pos.x and data.pos.y and data.pos.z then
                data.pos = string.format("[%.4f %.4f %.4f]", data.pos.x, data.pos.y, data.pos.z)
            elseif #data.pos == 3 then
                data.pos = string.format("[%.4f %.4f %.4f]", data.pos[1], data.pos[2], data.pos[3])
            end
        elseif type(data.pos) == "string" then
            if not string.match(data.pos, "^%[.*%]$") then
                local x, y, z = string.match(data.pos, "([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
                if x and y and z then
                    data.pos = string.format("[%.4f %.4f %.4f]", tonumber(x), tonumber(y), tonumber(z))
                end
            end
        end
    end

    if data.ang then
        if type(data.ang) == "table" then
            if data.ang.p and data.ang.y and data.ang.r then
                data.ang = string.format("{%.4f %.4f %.4f}", data.ang.p, data.ang.y, data.ang.r)
            elseif #data.ang == 3 then
                data.ang = string.format("{%.4f %.4f %.4f}", data.ang[1], data.ang[2], data.ang[3])
            end
        elseif type(data.ang) == "string" then
            if not string.match(data.ang, "^{.*}$") then
                local p, y, r = string.match(data.ang, "([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
                if p and y and r then
                    data.ang = string.format("{%.4f %.4f %.4f}", tonumber(p), tonumber(y), tonumber(r))
                end
            end
        end
    end

    local formattedJSON = FormatJSON(data)

    local editorContainer = vgui.Create("DPanel", panel)
    editorContainer:Dock(FILL)
    editorContainer:DockMargin(0, 0, 0, 60)
    editorContainer.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, SYNTAX_COLORS.background)
        surface.SetDrawColor(100, 100, 120, 150)
        surface.DrawOutlinedRect(0, 0, w, h, 2)
    end

    local lineNumbers = vgui.Create("DPanel", editorContainer)
    lineNumbers:SetWide(60)
    lineNumbers:Dock(LEFT)
    lineNumbers.Paint = function(self, w, h)
        draw.RoundedBoxEx(8, 0, 0, w, h, Color(20, 20, 30), true, false, true, false)
        surface.SetDrawColor(100, 100, 120, 100)
        surface.DrawRect(w - 1, 0, 1, h)

        local text = textEntry and textEntry:GetValue() or ""
        local lines = string.Split(text, "\n")

        surface.SetFont("RareloadEditorSmall")
        for i = 1, #lines do
            local y = (i - 1) * 20 + 8
            if y < h then
                draw.SimpleText(tostring(i), "RareloadEditorSmall", w - 8, y, SYNTAX_COLORS.line_number, TEXT_ALIGN_RIGHT,
                    TEXT_ALIGN_TOP)
            end
        end
    end

    local textEntry = vgui.Create("DTextEntry", editorContainer)
    textEntry:Dock(FILL)
    textEntry:DockMargin(0, 8, 8, 8)
    textEntry:SetMultiline(true)
    textEntry:SetFont("RareloadEditor")
    textEntry:SetUpdateOnType(true)
    textEntry:SetValue(formattedJSON)
    textEntry:SetTextColor(Color(220, 220, 230))

    local tokens = {}
    local lastValidJSON = formattedJSON
    local validationTimer = nil

    textEntry.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(25, 25, 35))

        if not self:HasFocus() then
            local text = self:GetValue()
            local lines = string.Split(text, "\n")
            local lineHeight = 20

            tokens = TokenizeJSON(text)

            local charX, charY = 8, 8
            local textPos = 1

            for lineNum, line in ipairs(lines) do
                charX = 8
                charY = (lineNum - 1) * lineHeight + 8

                if charY < h + lineHeight and charY > -lineHeight then
                    for i = 1, #line do
                        local char = string.sub(line, i, i)
                        local color = SYNTAX_COLORS.punctuation

                        for _, token in ipairs(tokens) do
                            if textPos >= token.start and textPos <= token.stop then
                                color = SYNTAX_COLORS[token.type] or SYNTAX_COLORS.punctuation
                                break
                            end
                        end

                        surface.SetFont("RareloadEditor")
                        surface.SetTextColor(color)
                        surface.SetTextPos(charX, charY)
                        surface.DrawText(char)

                        local charWidth = surface.GetTextSize(char) or 8
                        charX = charX + charWidth
                        textPos = textPos + 1
                    end
                    textPos = textPos + 1
                end
            end

            return
        end

        derma.SkinHook("Paint", "TextEntry", self, w, h)
    end

    local function updateHeight()
        lineNumbers:InvalidateLayout()
    end

    updateHeight()

    local statusPanel = vgui.Create("DPanel", panel)
    statusPanel:Dock(BOTTOM)
    statusPanel:SetTall(50)
    statusPanel:DockMargin(0, 8, 0, 0)

    local statusLabel = vgui.Create("DLabel", statusPanel)
    statusLabel:Dock(FILL)
    statusLabel:SetFont("DermaDefault")
    statusLabel:SetText("✓ Valid JSON")
    statusLabel:SetTextColor(Color(100, 200, 100))
    statusLabel:DockMargin(15, 0, 0, 0)
    statusLabel:SetContentAlignment(4)

    local function validateJSON()
        local jsonText = textEntry:GetValue()
        local ok, result = pcall(util.JSONToTable, jsonText)

        if ok and istable(result) then
            statusLabel:SetText("✓ Valid JSON - Ready to save")
            statusLabel:SetTextColor(Color(100, 200, 100))
            statusPanel.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(100, 200, 100, 40))
                surface.SetDrawColor(100, 200, 100, 180)
                surface.SetMaterial(Material("icon16/tick.png"))
                surface.DrawTexturedRect(8, h / 2 - 8, 16, 16)
            end
            lastValidJSON = jsonText
            return true, result
        else
            local errorMsg = tostring(result or "Unknown error")
            if string.len(errorMsg) > 60 then
                errorMsg = string.sub(errorMsg, 1, 60) .. "..."
            end
            statusLabel:SetText("✗ " .. errorMsg)
            statusLabel:SetTextColor(Color(255, 100, 100))
            statusPanel.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(255, 100, 100, 40))
                surface.SetDrawColor(255, 100, 100, 180)
                surface.SetMaterial(Material("icon16/exclamation.png"))
                surface.DrawTexturedRect(8, h / 2 - 8, 16, 16)
            end
            return false, nil
        end
    end

    textEntry.OnValueChange = function(self)
        if validationTimer then timer.Remove(validationTimer) end
        validationTimer = timer.Simple(0.3, function()
            validateJSON()
            updateHeight()
            tokens = TokenizeJSON(self:GetValue())
            self:InvalidateLayout()
        end)
    end

    local buttonPanel = vgui.Create("DPanel", panel)
    buttonPanel:Dock(BOTTOM)
    buttonPanel:SetTall(50)
    buttonPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(40, 40, 50, 100))
    end

    local formatBtn = vgui.Create("DButton", buttonPanel)
    formatBtn:SetText("Format")
    formatBtn:SetWide(80)
    formatBtn:Dock(LEFT)
    formatBtn:DockMargin(10, 8, 5, 8)
    formatBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and Color(100, 120, 255, 255) or Color(80, 100, 200, 255)
        draw.RoundedBox(6, 0, 0, w, h, color)
        draw.SimpleText("Format", "DermaDefault", w / 2, h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
    formatBtn.DoClick = function()
        local valid, parsedData = validateJSON()
        if valid then
            local beautified = FormatJSON(parsedData)
            textEntry:SetValue(beautified)
            updateHeight()
        end
    end

    local resetBtn = vgui.Create("DButton", buttonPanel)
    resetBtn:SetText("Reset")
    resetBtn:SetWide(80)
    resetBtn:Dock(LEFT)
    resetBtn:DockMargin(0, 8, 5, 8)
    resetBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and Color(140, 140, 140) or Color(120, 120, 120)
        draw.RoundedBox(6, 0, 0, w, h, color)
        draw.SimpleText("Reset", "DermaDefault", w / 2, h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    resetBtn.DoClick = function()
        textEntry:SetValue(formattedJSON)
        updateHeight()
        validateJSON()
    end

    local saveBtn = vgui.Create("DButton", buttonPanel)
    saveBtn:SetText("Save Changes")
    saveBtn:Dock(FILL)
    saveBtn:DockMargin(0, 8, 10, 8)
    saveBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and Color(100, 200, 100) or Color(80, 180, 80)
        draw.RoundedBox(6, 0, 0, w, h, color)
        draw.SimpleText("Save Changes", "DermaDefault", w / 2, h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
    saveBtn.DoClick = function()
        local valid, newData = validateJSON()

        if not valid then
            if ShowNotification then
                ShowNotification("Cannot save invalid JSON!", NOTIFY_ERROR)
            end
            return
        end

        if newData.pos and type(newData.pos) == "table" and newData.pos.x and newData.pos.y and newData.pos.z then
            newData.pos = string.format("[%.4f %.4f %.4f]", newData.pos.x, newData.pos.y, newData.pos.z)
        end
        if newData.ang and type(newData.ang) == "table" and newData.ang.p and newData.ang.y and newData.ang.r then
            newData.ang = string.format("{%.4f %.4f %.4f}", newData.ang.p, newData.ang.y, newData.ang.r)
        end

        if onSave then
            onSave(newData)
        end
    end

    validateJSON()

    return panel
end

if CLIENT then
    net.Receive("RareloadReloadData", function()
        if _G.LoadData then
            _G.LoadData()
        end
    end)
end
