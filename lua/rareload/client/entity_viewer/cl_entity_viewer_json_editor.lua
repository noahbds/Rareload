RARELOAD = RARELOAD or {}
RARELOAD.JSONEditor = RARELOAD.JSONEditor or {}

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
                if RARELOAD.DataUtils.ParsePositionString and RARELOAD.DataUtils.ParsePositionString(potentialVector) then
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
                if RARELOAD.DataUtils.ParseAngleString and RARELOAD.DataUtils.ParseAngleString(potentialAngle) then
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
        -- Check if it's an empty table first
        local isEmpty = true
        for _ in pairs(data) do
            isEmpty = false
            break
        end
        
        if isEmpty then
            -- For empty tables, check if the original was an array
            -- We'll default to [] for empty tables as it's more common
            return "[]"
        end
        
        local isArray = true
        local count = 0

        for k, v in pairs(data) do
            count = count + 1
            if type(k) ~= "number" or k ~= count then
                isArray = false
                break
            end
        end

        if isArray then
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

function RARELOAD.JSONEditor.Create(parent, data, isNPC, onSave)
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(FILL)
    panel.Paint = function() end

    local function getLineHeight()
        surface.SetFont("RareloadEditor")
        local _, h = surface.GetTextSize("Wg")
        return math.max(h, 18)
    end

    if data.pos then
        data.pos = RARELOAD.DataUtils.FormatPositionForJSON(data.pos, 4)
    end

    if data.ang then
        data.ang = RARELOAD.DataUtils.FormatAngleForJSON(data.ang, 4)
    end

    local formattedJSON = FormatJSON(data)

    -- Shared scroll so line numbers and text move together
    local editorScroll = vgui.Create("DScrollPanel", panel)
    editorScroll:Dock(FILL)
    editorScroll:DockMargin(0, 0, 0, 60)
    
    local editorContainer = vgui.Create("DPanel", editorScroll:GetCanvas())
    editorContainer:Dock(TOP)
    editorContainer:SetTall(600)
    editorContainer:DockMargin(0, 0, 0, 0)
    editorContainer.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, SYNTAX_COLORS.background)
        surface.SetDrawColor(100, 100, 120, 150)
        surface.DrawOutlinedRect(0, 0, w, h, 2)
    end

    ---@class DTextEntry
    local textEntry = vgui.Create("DTextEntry", editorContainer)
    textEntry:Dock(FILL)
    textEntry:DockMargin(0, 8, 8, 8)
    textEntry:SetMultiline(true)
    textEntry:SetFont("RareloadEditor")
    -- Ensure one visual line per logical line for accurate numbering
    if textEntry.SetWrap then textEntry:SetWrap(false) end
    textEntry:SetUpdateOnType(true)
    textEntry:SetValue(formattedJSON)
    textEntry:SetTextColor(Color(220, 220, 230))
    textEntry:SetDrawBackground(false)
    textEntry:SetPaintBackground(false)
    textEntry:SetCursorColor(Color(255, 255, 255))

    local lineNumbers = vgui.Create("DPanel", editorContainer)
    lineNumbers:SetWide(60)
    lineNumbers:Dock(LEFT)
    lineNumbers.Paint = function(self, w, h)
        draw.RoundedBoxEx(8, 0, 0, w, h, Color(20, 20, 30), true, false, true, false)
        surface.SetDrawColor(100, 100, 120, 100)
        surface.DrawRect(w - 1, 0, 1, h)

        local text = textEntry and textEntry:GetValue() or ""
        local lines = string.Split(text, "\n")
        local lineHeight = getLineHeight()
        local scroll = 0
        if editorScroll and editorScroll:GetVBar() then
            scroll = editorScroll:GetVBar():GetScroll() or 0
        end
        local startLine = math.floor(scroll / lineHeight) + 1
        local visibleHeight = editorScroll and editorScroll:GetTall() or h
        -- Ensure visibleHeight is at least something reasonable if GetTall returns 0
        if visibleHeight < 50 then visibleHeight = 600 end
        
        local visibleLines = math.ceil(visibleHeight / lineHeight) + 2
        local endLine = math.min(#lines, startLine + visibleLines)

        for i = startLine, endLine do
            local y = (i - 1) * lineHeight + 8
            draw.SimpleText(tostring(i), "RareloadEditorSmall", w - 8, y, SYNTAX_COLORS.line_number, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        end
    end

    local tokens = {}
    local lastValidJSON = formattedJSON
    local validationTimer = nil

    -- Override Paint completely to control background
    textEntry.Paint = function(self, w, h)
        -- Draw dark background first
        draw.RoundedBox(4, 0, 0, w, h, SYNTAX_COLORS.background)
        
        -- Let derma draw the text and cursor with our dark background
        self:DrawTextEntryText(self:GetTextColor(), self:GetHighlightColor(), self:GetCursorColor())
        -- Highlight current line
        local caret = self.GetCaretPos and self:GetCaretPos() or 0
        local text = self:GetValue() or ""
        local before = string.sub(text, 1, caret)
        local lineIndex = select(2, string.gsub(string.sub(before, 1, #before), "\n", "\n")) + 1
        local lineHeight = getLineHeight()
        local y = (lineIndex - 1) * lineHeight
        surface.SetDrawColor(60, 60, 80, 60)
        surface.DrawRect(60, y, w - 60, lineHeight)
    end

    local function updateHeight()
        if not IsValid(textEntry) or not IsValid(editorContainer) then return end
        local text = textEntry:GetValue() or ""
        local _, count = string.gsub(text, "\n", "")
        local lineCount = count + 1
        local lineHeight = getLineHeight()
        -- Add extra buffer to ensure we never cut off the last lines
        local needed = (lineCount * lineHeight) + 400
        
        if editorContainer:GetTall() < needed then
            editorContainer:SetTall(needed)
            if IsValid(editorScroll) then editorScroll:InvalidateLayout(true) end
        end
        if IsValid(lineNumbers) then lineNumbers:InvalidateLayout(true) end
    end

    -- Ensure height is updated when text changes or on init
    textEntry.OnValueChange = function(self)
        if validationTimer then timer.Remove(validationTimer) end
        validationTimer = timer.Simple(0.3, function()
            validateJSON()
            tokens = TokenizeJSON(self:GetValue())
            self:InvalidateLayout()
            if IsValid(lineNumbers) then lineNumbers:InvalidateLayout(true) end
            scrollToCaret()
        end)
        -- Update height immediately to prevent scroll lock
        updateHeight()
    end

    local function scrollToCaret()
        if not IsValid(textEntry) or not IsValid(editorScroll) then return end
        local caret = textEntry.GetCaretPos and textEntry:GetCaretPos() or 0
        local text = textEntry:GetValue() or ""
        local before = string.sub(text, 1, caret)
        local lineIndex = select(2, string.gsub(before, "\n", "")) + 1
        local lineHeight = getLineHeight()
        local vbar = editorScroll:GetVBar()
        if not vbar then return end
        local scroll = vbar:GetScroll() or 0
        local viewportH = editorScroll:GetTall()
        local y = (lineIndex - 1) * lineHeight
        if y < scroll then
            vbar:SetScroll(y)
        elseif (y + lineHeight) > (scroll + viewportH) then
            vbar:SetScroll((y + lineHeight) - viewportH)
        end
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
                local mat = Material("icon16/tick.png")
                if not mat:IsError() then
                    surface.SetMaterial(mat)
                    surface.DrawTexturedRect(8, h / 2 - 8, 16, 16)
                end
            end
            lastValidJSON = jsonText
            return true, result
        else
            local errorMsg = "Invalid JSON syntax"
            if result and type(result) == "string" then
                errorMsg = tostring(result)
                if string.len(errorMsg) > 60 then
                    errorMsg = string.sub(errorMsg, 1, 60) .. "..."
                end
            end
            statusLabel:SetText("✗ " .. errorMsg)
            statusLabel:SetTextColor(Color(255, 100, 100))
            statusPanel.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(255, 100, 100, 40))
                surface.SetDrawColor(255, 100, 100, 180)
                local mat = Material("icon16/exclamation.png")
                if not mat:IsError() then
                    surface.SetMaterial(mat)
                    surface.DrawTexturedRect(8, h / 2 - 8, 16, 16)
                end
            end
            return false, nil
        end
    end

    textEntry.OnValueChange = function(self)
        if validationTimer then timer.Remove(validationTimer) end
        validationTimer = timer.Simple(0.3, function()
            validateJSON()
            tokens = TokenizeJSON(self:GetValue())
            self:InvalidateLayout()
            if IsValid(lineNumbers) then lineNumbers:InvalidateLayout(true) end
            scrollToCaret()
        end)
        -- Update height immediately to prevent scroll lock
        updateHeight()
    end

    -- Keep scroll synced when navigating with arrow keys and Enter
    textEntry.OnKeyCodeTyped = function(self, code)
        -- Update height when adding/removing lines
        if code == KEY_ENTER or code == KEY_BACKSPACE or code == KEY_DELETE then
            timer.Simple(0, function()
                if not IsValid(self) then return end
                updateHeight()
            end)
        end
        -- After movement, ensure caret is in view
        timer.Simple(0, function()
            scrollToCaret()
            if IsValid(lineNumbers) then lineNumbers:InvalidateLayout(true) end
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
        if not newData then
            if ShowNotification then
                ShowNotification("No data to save!", NOTIFY_ERROR)
            end
            return
        end
        if newData.pos then
            newData.pos = RARELOAD.DataUtils.FormatPositionForJSON(newData.pos, 4)
        end
        if newData.ang then
            newData.ang = RARELOAD.DataUtils.FormatAngleForJSON(newData.ang, 4)
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
