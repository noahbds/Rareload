RARELOAD = RARELOAD or {}
RARELOAD.JSONEditor = RARELOAD.JSONEditor or {}

local STRIP_KEYS = { rawData = true, id = true }

local function SanitizeTable(input)
  if not istable(input) then return input end

  local out = {}
  for k, v in pairs(input) do
    if STRIP_KEYS[k] then continue end

    if isvector(v) then
      out[k] = { x = v.x, y = v.y, z = v.z, __rareload_type = "Vector" }
    elseif isangle(v) then
      out[k] = { p = v.p, y = v.y, r = v.r, __rareload_type = "Angle" }
    elseif istable(v) then
      out[k] = SanitizeTable(v)
    else
      out[k] = v
    end
  end
  return out
end

local function RestoreTable(input)
  if not istable(input) then return input end

  local out = {}
  for k, v in pairs(input) do
    if istable(v) then
      if v.__rareload_type == "Vector" then
        out[k] = Vector(v.x or 0, v.y or 0, v.z or 0)
      elseif v.__rareload_type == "Angle" then
        out[k] = Angle(v.p or 0, v.y or 0, v.r or 0)
      else
        out[k] = RestoreTable(v)
      end
    else
      out[k] = v
    end
  end
  return out
end

local function SplitChunks(str, size)
  local chunks = {}
  for i = 1, #str, size do
    chunks[#chunks + 1] = string.sub(str, i, i + size - 1)
  end
  return chunks
end

function RARELOAD.JSONEditor.Create(parent, data, isNPC, onSave)
  local panel = vgui.Create("DPanel", parent)
  panel:Dock(FILL)
  panel.Paint = function() end

  local editData = SanitizeTable(data.rawData or data)
  local formattedJSON = util.TableToJSON(editData, true)

  local html = vgui.Create("DHTML", panel)
  html:Dock(FILL)
  html:DockMargin(0, 0, 0, 50)

  html:SetHTML([[
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { background: #1d1f21; overflow: hidden; width: 100vw; height: 100vh; }
        #editor { position: absolute; top: 0; left: 0; right: 0; bottom: 22px; font-size: 13px; }
        #status {
            position: fixed; bottom: 0; left: 0; right: 0;
            height: 22px; background: #1a1c1e; display: flex;
            align-items: center; padding: 0 10px;
            font-family: 'Consolas', monospace; font-size: 11px;
            color: #6e7681; border-top: 1px solid #2d2f33;
        }
        #status.error { color: #e74c3c; }
        #status.ok { color: #2ecc71; }
    </style>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.2/ace.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.2/ext-language_tools.min.js"></script>
</head>
<body>
    <div id="editor"></div>
    <div id="status">Ready</div>
    <script>
        ace.require("ace/ext/language_tools");
        var editor = ace.edit("editor");
        editor.setTheme("ace/theme/tomorrow_night");
        editor.session.setMode("ace/mode/json");
        editor.setOptions({
            fontSize: "13px",
            useWorker: false,
            wrap: true,
            showPrintMargin: false,
            tabSize: 2,
            useSoftTabs: true,
            enableBasicAutocompletion: true,
            enableLiveAutocompletion: false,
            enableSnippets: false
        });

        var statusEl = document.getElementById("status");
        var Range = ace.require("ace/range").Range;
        var _buf = [];
        function _chunk(hex) { _buf.push(hex); }
        function _commit() {
            var hex = _buf.join("");
            var str = "";
            for (var i = 0; i < hex.length; i += 2) {
                str += String.fromCharCode(parseInt(hex.substr(i, 2), 16));
            }
            editor.setValue(str, -1);
            editor.clearSelection();
            _buf = [];
            statusEl.className = "";
            statusEl.textContent = "Ready";
        }

        function parseJSONError(err, src) {
            var msg = err.message || String(err);
            var mLC = msg.match(/line\s+(\d+)\s+column\s+(\d+)/i);
            if (mLC) return { line: parseInt(mLC[1], 10) - 1, col: parseInt(mLC[2], 10) - 1, message: msg };

            var mPos = msg.match(/at position\s+(\d+)/i);
            if (mPos) {
                var offset = parseInt(mPos[1], 10);
                var before = src.slice(0, offset);
                var lines = before.split("\n");
                return { line: lines.length - 1, col: lines[lines.length - 1].length, message: msg };
            }
            return { line: -1, col: -1, message: msg };
        }

        function clearErrorState() {
            editor.session.clearAnnotations();
            if (window.lastErrorMarker) {
                editor.session.removeMarker(window.lastErrorMarker);
                window.lastErrorMarker = null;
            }
        }

        editor.session.on("change", function() {
            if (window.validateTimer) clearTimeout(window.validateTimer);
            window.validateTimer = setTimeout(function() {
                var src = editor.getValue();
                if (!src.trim()) {
                    clearErrorState();
                    statusEl.className = "";
                    statusEl.textContent = "Ready";
                    return;
                }
                try {
                    JSON.parse(src);
                    clearErrorState();
                    statusEl.className = "ok";
                    statusEl.textContent = "\u2714 Valid JSON";
                } catch (e) {
                    var info = parseJSONError(e, src);
                    clearErrorState();
                    statusEl.className = "error";
                    if (info.line >= 0) {
                        statusEl.textContent = "\u2718 Line " + (info.line + 1) + ", Col " + (info.col + 1) + " \u2014 " + info.message.split(" at ")[0].trim();
                        editor.session.setAnnotations([{ row: info.line, column: info.col, text: info.message, type: "error" }]);
                        window.lastErrorMarker = editor.session.addMarker(new Range(info.line, 0, info.line, Infinity), "ace_error_line", "fullLine");
                        var lineHeight = editor.renderer.lineHeight || 16;
                        var visibleRows = Math.floor((editor.renderer.$size.scrollerHeight || editor.renderer.$size.height) / lineHeight);
                        editor.renderer.scrollToRow(Math.max(0, info.line - visibleRows + 4));
                    } else {
                        statusEl.textContent = "\u2718 " + info.message;
                    }
                }
            }, 300);
        });

        function getContent() { return editor.getValue(); }
    </script>
</body>
</html>
    ]])

  local function ToHex(str)
    return (string.gsub(str, ".", function(c)
      return string.format("%02x", string.byte(c))
    end))
  end

  local function LoadIntoEditor(jsonStr)
    if not IsValid(html) then return end
    local hex = ToHex(jsonStr)
    local chunks = SplitChunks(hex, 8000)
    for _, chunk in ipairs(chunks) do
      html:RunJavascript("_chunk('" .. chunk .. "')")
    end
    html:RunJavascript("_commit()")
  end

  timer.Simple(0.4, function()
    LoadIntoEditor(formattedJSON)
  end)

  local actionBar = vgui.Create("DPanel", panel)
  actionBar:Dock(BOTTOM)
  actionBar:SetTall(46)
  actionBar:DockMargin(0, 4, 0, 0)
  actionBar.Paint = function(self, w, h)
    draw.RoundedBox(0, 0, 0, w, h, THEME.backgroundDark)
  end

  local fmtBtn = vgui.Create("DButton", actionBar)
  fmtBtn:SetText("Format")
  fmtBtn:SetFont("RareloadBody")
  fmtBtn:SetTextColor(THEME.textSecondary)
  fmtBtn:Dock(LEFT)
  fmtBtn:SetWide(90)
  fmtBtn:DockMargin(15, 6, 8, 6)
  fmtBtn.Paint = function(self, w, h)
    local c = self:IsHovered() and THEME.surfaceVariant or THEME.surface
    draw.RoundedBox(6, 0, 0, w, h, c)
  end

  fmtBtn.DoClick = function()
    html:AddFunction("gmod", "receiveForFormat", function(txt)
      local ok, tbl = pcall(util.JSONToTable, txt)
      if ok and istable(tbl) then
        local pretty = util.TableToJSON(tbl, true)
        if IsValid(html) then
          LoadIntoEditor(pretty)
        end
      else
        ShowNotification("Cannot format: invalid JSON!", NOTIFY_ERROR)
      end
    end)
    html:RunJavascript("gmod.receiveForFormat(getContent())")
  end

  local saveBtn = vgui.Create("DButton", actionBar)
  saveBtn:SetText("   Save Changes")
  saveBtn:SetFont("RareloadBody")
  saveBtn:SetTextColor(THEME.textPrimary)
  saveBtn:Dock(RIGHT)
  saveBtn:SetWide(140)
  saveBtn:DockMargin(8, 6, 15, 6)
  saveBtn.Paint = function(self, w, h)
    local c = self:IsHovered() and Color(46, 184, 93) or THEME.success
    draw.RoundedBox(6, 0, 0, w, h, c)
    surface.SetDrawColor(255, 255, 255, 200)
    surface.SetMaterial(Material("icon16/disk.png"))
    surface.DrawTexturedRect(12, h / 2 - 8, 16, 16)
  end

  saveBtn.DoClick = function()
    html:AddFunction("gmod", "send", function(txt)
      local ok, tbl = pcall(util.JSONToTable, txt)
      if not ok or not istable(tbl) then
        ShowNotification("Invalid JSON — fix errors before saving.", NOTIFY_ERROR)
        return
      end

      local restored = RestoreTable(tbl)
      if onSave then onSave(restored) end
    end)
    html:RunJavascript("gmod.send(getContent())")
  end

  return panel
end
