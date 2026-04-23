RARELOAD = RARELOAD or {}
RARELOAD.JSONEditor = RARELOAD.JSONEditor or {}

local function SanitizeData(t)
    if not istable(t) then return t end
    local clean = {}
    for k, v in pairs(t) do
        if k == "rawData" or k == "id" then continue end -- Strip internal bloat

        if isvector(v) then
            clean[k] = { x = v.x, y = v.y, z = v.z, __rareload_type = "Vector" }
        elseif isangle(v) then
            clean[k] = { p = v.p, y = v.y, r = v.r, __rareload_type = "Angle" }
        elseif istable(v) then
            clean[k] = SanitizeData(v)
        else
            clean[k] = v
        end
    end
    return clean
end

function RARELOAD.JSONEditor.Create(parent, data, isNPC, onSave)
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(FILL)
    panel.Paint = function() end

    -- Use full raw data if available, and sanitize it for JSON
    local editData = SanitizeData(data.rawData or data)
    local formattedJSON = util.TableToJSON(editData, true)

    local html = vgui.Create("DHTML", panel)
    html:Dock(FILL)
    html:DockMargin(10, 10, 10, 60)

    html:SetHTML([[
        <html>
        <head>
            <style>body { margin:0; background:#1d1f21; overflow:hidden; }</style>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.4.12/ace.js"></script>
        </head>
        <body>
            <div id="editor" style="width:100%; height:100%;"></div>
            <script>
                var editor = ace.edit("editor");
                editor.setTheme("ace/theme/tomorrow_night");
                editor.session.setMode("ace/mode/json");
                editor.setOptions({ fontSize: "14px", useWorker: false, wrap: true });
                function setContent(t) { editor.setValue(t, -1); }
                function getContent() { return editor.getValue(); }
            </script>
        </body>
        </html>
    ]])

    timer.Simple(0.3, function()
        if IsValid(html) then
            -- Safely inject the string using string.JavascriptSafe to avoid syntax errors
            html:RunJavascript("setContent('" .. string.JavascriptSafe(formattedJSON) .. "')")
        end
    end)

    local save = vgui.Create("DButton", panel)
    save:Dock(BOTTOM)
    save:SetTall(35)
    save:DockMargin(10, 10, 10, 10)
    save:SetText("Save Changes")
    save.DoClick = function()
        html:AddFunction("gmod", "send", function(txt)
            local ok, tbl = pcall(util.JSONToTable, txt)
            if ok and istable(tbl) and onSave then
                onSave(tbl)
            else
                ShowNotification("Invalid JSON syntax!", NOTIFY_ERROR)
            end
        end)
        html:RunJavascript("gmod.send(getContent())")
    end
end
