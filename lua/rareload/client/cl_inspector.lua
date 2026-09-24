-- Object inspector (REWRITE_PLAN.md §21.6, F29): the objects inside one save, as an overlay above the
-- timeline. A rail to search, sort and filter; a grid of cards; a detail pane with the object's facts
-- and actions (highlight, teleport, look at, copy) and, with rareload_manage_objects, freeze and
-- gravity flags, delete (one or all shown) and a coloured JSON editor that checks the text as you type.

RARELOAD.Inspector = RARELOAD.Inspector or {}
local Inspector = RARELOAD.Inspector
local L, UI, State, Util = RARELOAD.L, RARELOAD.UI, RARELOAD.State, RARELOAD.Util
local C, sc = UI.C, UI.sc

local KINDS = { "all", "entities", "npcs", "vehicles", "weapons" }
local SORTS = { "name", "distance", "health" }
local MAX_CARDS = 150

local function request(op, args) RARELOAD.Net.Request(op, args) end
local function canManage() return RARELOAD.Can(LocalPlayer(), "rareload_manage_objects") end

local function isWeapon(o) return string.StartsWith(string.lower(o.class or ""), "weapon_") end

-- Which saved objects are on the map, rescanned at most once a second (the painters ask every frame).
local liveCache, liveAt = {}, 0
local function isLive(id)
    if RealTime() - liveAt > 1 then
        liveCache, liveAt = {}, RealTime()
        for _, ent in ents.Iterator() do
            local rid = ent:GetNWString("rl_id", "")
            if rid ~= "" then liveCache[rid] = true end
        end
    end
    return liveCache[id] == true
end

local function distanceTo(o)
    local p = Util.ToVector(o.pos)
    return p and LocalPlayer():GetPos():Distance(p) or math.huge
end

-- JSON editor ---------------------------------------------------------------------------------------

-- The coloured editor: Ace (the code editor v4 used) in a DHTML page, with JSON colours, folding,
-- bracket matching, search (Ctrl+F), Ctrl+S to save, the error line marked as you type and a count of
-- changed keys. Ace comes from cdnjs; without internet the editor falls back to a plain text box.
local ACE = "https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.2/"
local EDITOR_HTML = [[
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  html, body { margin: 0; height: 100%; background: #121419; overflow: hidden; }
  #editor { position: absolute; inset: 0; font-size: 14px; }
  .ace_editor, .ace_gutter { background: #121419 !important; }
  .ace_gutter { color: #5c616e !important; }
  .ace_active-line, .ace_gutter-active-line { background: #1c1f27 !important; }
  .rl-error { position: absolute; background: rgba(240, 80, 80, 0.22); border-bottom: 1px solid #f05050; }
</style>
<script src="]] .. ACE .. [[ace.min.js"></script>
</head><body><div id="editor"></div><script>
var editor, original = {}, marker = null, timer = null, parts = [];
if (window.ace) {
  ace.config.set("basePath", "]] .. ACE .. [[");
  editor = ace.edit("editor", {
    mode: "ace/mode/json", theme: "ace/theme/tomorrow_night", useWorker: false, showPrintMargin: false,
    tabSize: 2, useSoftTabs: true, wrap: true, fontSize: "14px", scrollPastEnd: 0.3, highlightActiveLine: true
  });
  editor.commands.addCommand({ name: "save", bindKey: { win: "Ctrl-S", mac: "Command-S" },
    exec: function () { rareload.save(editor.getValue()); } });
  editor.session.on("change", function () { clearTimeout(timer); timer = setTimeout(check, 200); });
}
var push = function (part) { parts.push(part); };
var load = function (isOriginal) {
  var text = parts.join(""); parts = [];
  if (isOriginal) { try { original = JSON.parse(text); } catch (e) { original = {}; } }
  editor.session.setValue(text);
  editor.focus();
  check();
};
var format = function () {
  try { editor.session.setValue(JSON.stringify(JSON.parse(editor.getValue()), null, 2)); } catch (e) {}
};
var where = function (msg, src) {
  var m = msg.match(/line (\d+) column (\d+)/i);
  if (m) return { row: +m[1] - 1, col: +m[2] - 1 };
  m = msg.match(/position (\d+)/i);
  if (!m) return null;
  var lines = src.slice(0, +m[1]).split("\n");
  return { row: lines.length - 1, col: lines[lines.length - 1].length };
};
var check = function () {
  var src = editor.getValue(), s = editor.session;
  if (marker !== null) { s.removeMarker(marker); marker = null; }
  s.clearAnnotations();
  try {
    var t = JSON.parse(src), changed = 0, k;
    if (t === null || typeof t !== "object" || Array.isArray(t)) throw new Error("the object must be a JSON object { }");
    for (k in t) if (JSON.stringify(t[k]) !== JSON.stringify(original[k])) changed++;
    for (k in original) if (!(k in t)) changed++;
    rareload.status(true, 0, 0, "", changed);
  } catch (e) {
    var msg = String(e.message || e).replace(/ in JSON.*$/, ""), at = where(String(e.message || e), src);
    if (at) {
      var Range = ace.require("ace/range").Range;
      marker = s.addMarker(new Range(at.row, 0, at.row, Infinity), "rl-error", "fullLine");
      s.setAnnotations([{ row: at.row, column: at.col, text: msg, type: "error" }]);
    }
    rareload.status(false, at ? at.row + 1 : 0, at ? at.col + 1 : 0, msg, 0);
  }
};
// Tells Lua the page is up once its callbacks exist.
(function ready() { if (window.rareload && rareload.ready) rareload.ready(!!window.ace); else setTimeout(ready, 50); })();
</script></body></html>]]

-- Feeds `text` to the page in pieces, never cutting a UTF-8 character, then loads it.
local function sendText(html, text, isOriginal)
    local i = 1
    while i <= #text do
        local j = math.min(i + 16000, #text)
        while j < #text and bit.band(string.byte(text, j + 1), 0xC0) == 0x80 do j = j - 1 end
        html:QueueJavascript("push(\"" .. string.JavascriptSafe(string.sub(text, i, j)) .. "\")")
        i = j + 1
    end
    html:QueueJavascript("load(" .. tostring(isOriginal == true) .. ")")
end

-- The Ace editor. Calls onReady(api) once Ace loaded, or onFail() when it can't load.
-- api = { get(fn(text)), set(text), format() }; onStatus(ok, line, col, why, changed) runs as you type.
local function aceEditor(parent, json, onStatus, onSave, onReady, onFail)
    local html = vgui.Create("DHTML", parent)
    html:Dock(FILL)
    local api, pending, done = {}, nil, false
    local function fail()
        if done then return end
        done = true
        html:Remove()
        onFail()
    end
    html:AddFunction("rareload", "ready", function(ok)
        if done then return end
        if not ok then return fail() end
        done = true
        sendText(html, json, true)
        onReady(api)
    end)
    html:AddFunction("rareload", "status", onStatus)
    html:AddFunction("rareload", "save", onSave)
    html:AddFunction("rareload", "text", function(text)
        if pending then pending(text) end
        pending = nil
    end)
    function api.get(fn)
        pending = fn
        html:QueueJavascript("rareload.text(editor.getValue())")
    end
    function api.set(text) sendText(html, text) end
    function api.format() html:QueueJavascript("format()") end

    html:SetHTML(EDITOR_HTML)
    timer.Simple(6, function() if IsValid(html) and not done then fail() end end)   -- the CDN didn't answer
    return html
end

-- The plain text box, checked in Lua; the same api as aceEditor.
local function plainEditor(parent, json, original, onStatus)
    local text = UI.TextEntry(parent, nil, true)
    text:Dock(FILL)
    text:SetValue(json)
    local function check()
        local ok, line, col, why = Util.CheckJSON(text:GetValue())
        local changed = 0
        local edited = ok and util.JSONToTable(text:GetValue())
        if edited then
            for k, v in pairs(edited) do
                if util.TableToJSON({ v }) ~= util.TableToJSON({ original[k] }) then changed = changed + 1 end
            end
            for k in pairs(original) do if edited[k] == nil then changed = changed + 1 end end
        end
        onStatus(ok, line, col, why, changed)
    end
    text.OnChange = function() timer.Create("Rareload.Inspector.Check", 0.25, 1, function() if IsValid(text) then check() end end) end
    check()
    return {
        get = function(fn) fn(text:GetValue()) end,
        set = function(value) text:SetValue(value) check() end,
        format = function()
            local t = util.JSONToTable(text:GetValue())
            if t then text:SetValue(util.TableToJSON(t, true)) check() end
        end,
    }
end

-- Only keys whose value changed are sent; the server checks each against the saved object (S6).
local function openEditor(entryId, objectId, json)
    local original = util.JSONToTable(json) or {}
    local frame = UI.Window({ title = L("inspector.edit_title"), subtitle = objectId, w = 860, h = 760, overlay = true })
    local status = { ok = true, changed = 0, loading = true }
    local editor

    local bar = vgui.Create("DPanel", frame)
    bar:Dock(BOTTOM)
    bar:SetTall(sc(36))
    bar:DockMargin(0, sc(8), 0, 0)
    bar.Paint = function() end

    local statusLine = vgui.Create("DPanel", frame)
    statusLine:Dock(BOTTOM)
    statusLine:SetTall(sc(22))
    statusLine:DockMargin(0, sc(6), 0, 0)
    statusLine.Paint = function(_, w, h)
        local msg, col, icon
        if status.loading then
            msg, col, icon = L("inspector.json_loading"), C.text3, "hourglass"
        elseif status.ok then
            msg, col, icon = L("inspector.json_ok"), C.ok, "accept"
        else
            msg, col, icon = status.line > 0 and L("inspector.json_error", status.line, status.col, status.why) or status.why, C.bad, "exclamation"
        end
        UI.DrawIcon(icon, 0, (h - sc(16)) / 2, sc(16))
        draw.SimpleText(UI.Clip(msg, "Rareload.Small", w * 0.6), "Rareload.Small", sc(22), h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local right = status.changed > 0 and L("inspector.json_changed", status.changed) or ""
        if status.plain then right = L("inspector.json_plain") .. (right ~= "" and "  ·  " .. right or "") end
        draw.SimpleText(right, "Rareload.Small", w, h / 2, status.changed > 0 and C.warn or C.text3, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local save
    local function onStatus(ok, line, col, why, changed)
        status = { ok = ok, line = tonumber(line) or 0, col = tonumber(col) or 0, why = why, changed = tonumber(changed) or 0,
            plain = status.plain }
        if IsValid(save) then save:SetEnabled(ok and status.changed > 0) end
    end
    local function send(text)
        local edited = util.JSONToTable(text or "")
        if not IsValid(frame) or not edited then return end
        local changes = {}
        for k, v in pairs(edited) do
            if util.TableToJSON({ v }) ~= util.TableToJSON({ original[k] }) then changes[k] = v end
        end
        if next(changes) then
            request("object.edit", { entryId = entryId, objectId = objectId, json = util.TableToJSON(changes) })
            UI.Notify(L("inspector.edit_sent"))
        end
        frame:Close()
    end

    aceEditor(frame, json, onStatus, send, function(api) editor = api end, function()
        status.plain = true
        editor = plainEditor(frame, json, original, onStatus)
    end)

    local format = UI.Button(bar, L("inspector.json_format"), function()
        if editor then editor.format() end
    end, { style = "ghost", icon = "text_align_left" })
    format:Dock(LEFT)
    format:SizeToLabel()
    local reset = UI.Button(bar, L("inspector.json_reset"), function()
        if editor then editor.set(json) end
    end, { style = "ghost", icon = "arrow_undo" })
    reset:Dock(LEFT)
    reset:DockMargin(sc(6), 0, 0, 0)
    reset:SizeToLabel()
    save = UI.Button(bar, L("inspector.edit_save"), function()
        if editor then editor.get(send) end
    end, { style = "success", solid = true, icon = "disk" })
    save:Dock(RIGHT)
    save:SizeToLabel()
    save:SetEnabled(false)
end

hook.Add("RareloadStateChanged", "Rareload.Inspector.Editor", function(what, p)
    if what ~= "def" or Inspector.waitingDef ~= p.objectId then return end
    Inspector.waitingDef = nil
    if Inspector.copyJson then
        Inspector.copyJson = nil
        SetClipboardText(p.json)
        return UI.Notify(L("inspector.copied", "JSON"))
    end
    openEditor(p.entryId, p.objectId, p.json)
end)

-- Highlight key of an object in this inspector.
local function highlightId(obj) return "obj:" .. tostring(obj.id) end

local function toggleHighlight(obj)
    local pos = Util.ToVector(obj.pos)
    if not pos then return end
    return RARELOAD.Highlight.Toggle("saved", highlightId(obj), {
        pos = pos, label = UI.ObjectName(obj.class, obj.model), live = function() return RARELOAD.World.FindLive(obj.id) end,
    })
end

-- Cards ---------------------------------------------------------------------------------------------

local function buildCard(parent, obj, isSelected, onClick)
    local card = vgui.Create("DButton", parent)
    card:SetText("")
    card:SetSize(sc(160), sc(196))
    local typeCol = isWeapon(obj) and C.warn or UI.KIND_COLORS[obj.kind] or C.text3
    card.Paint = function(self, w, h)
        local selected = isSelected(obj.id)
        self.anim = Lerp(FrameTime() * 10, self.anim or 0, (self:IsHovered() or selected) and 1 or 0)
        draw.RoundedBox(sc(10), 0, 0, w, h, UI.Mix(C.surface, C.accent, self.anim * 0.1))
        if selected then
            surface.SetDrawColor(C.accent)
            surface.DrawOutlinedRect(0, 0, w, h, sc(2))
        end
        draw.RoundedBoxEx(sc(6), 0, h - sc(4), w, sc(4), typeCol, false, false, true, true)
        draw.RoundedBox(sc(8), sc(8), sc(8), w - sc(16), sc(108), C.bgDark)
    end
    card.PaintOver = function(_, w)
        draw.SimpleText(UI.Clip(UI.ObjectName(obj.class, obj.model), "Rareload.Small", w - sc(16)), "Rareload.Small", w / 2, sc(124), C.text, TEXT_ALIGN_CENTER)
        local y = sc(144)
        if obj.maxHp and obj.maxHp > 0 then
            draw.RoundedBox(sc(3), sc(14), y, w - sc(28), sc(5), C.bgDark)
            draw.RoundedBox(sc(3), sc(14), y, (w - sc(28)) * math.Clamp((obj.hp or 0) / obj.maxHp, 0, 1), sc(5), UI.HealthColor(obj.hp, obj.maxHp))
            y = y + sc(12)
        end
        local d = distanceTo(obj)
        if d < math.huge then draw.SimpleText(L("inspector.units", math.Round(d)), "Rareload.Tiny", w / 2, y, C.text3, TEXT_ALIGN_CENTER) end
        if isLive(obj.id) then UI.DrawIcon("world", w - sc(28), sc(12), sc(16)) end
    end
    if UI.IsModel(obj.model) then
        local icon = vgui.Create("SpawnIcon", card)
        icon:SetPos(sc(8) + (sc(144) - sc(100)) / 2, sc(12))
        icon:SetSize(sc(100), sc(100))
        icon:SetModel(obj.model, obj.skin or 0)
        icon:SetMouseInputEnabled(false)
        icon:SetTooltip(false)
    end
    card.DoClick = function()
        surface.PlaySound("ui/buttonrollover.wav")
        onClick(obj.id)
    end
    return card
end

-- Detail pane ---------------------------------------------------------------------------------------

local function buildDetail(host, entryId, sel)
    local D = {}
    local function gap(p, b) p:DockMargin(0, 0, 0, sc(b or 8)) end

    D.model = UI.Model(host, "models/error.mdl", 26)
    D.model:Dock(TOP)
    D.model:SetTall(sc(170))
    gap(D.model)

    D.rows = UI.Rows(host, function()
        local o = sel()
        if not o then return {} end
        local live = isLive(o.id)
        local list = {
            { L("field.id"), o.id or "?" }, { L("field.class"), o.class or "?" }, { L("field.model"), o.model or "-", C.text2 },
            { L("field.kind"), L("kind." .. (isWeapon(o) and "weapons" or o.kind)), UI.KIND_COLORS[o.kind] },
            { L("field.position"), UI.Pos(o.pos) }, { L("field.angle"), UI.Pos(o.ang), C.text2 },
            { L("field.distance"), distanceTo(o) < math.huge and L("inspector.units", math.Round(distanceTo(o))) or "-", C.text2 },
            { L("field.status"), live and L("world.live") or L("world.missing"), live and C.ok or C.warn },
        }
        if o.maxHp and o.maxHp > 0 then list[#list + 1] = { L("field.health"), (o.hp or 0) .. " / " .. o.maxHp, UI.HealthColor(o.hp, o.maxHp) } end
        if o.skin and o.skin ~= 0 then list[#list + 1] = { L("field.skin"), tostring(o.skin) } end
        if o.scale then list[#list + 1] = { L("field.scale"), tostring(o.scale) } end
        if o.material and o.material ~= "" then list[#list + 1] = { L("field.material"), o.material } end
        if o.base then list[#list + 1] = { L("field.base"), L("base." .. o.base), C.vehicle } end
        if o.squad and o.squad ~= "" then list[#list + 1] = { L("field.squad"), o.squad, C.npc } end
        return list
    end)
    D.rows:Dock(TOP)
    gap(D.rows)

    D.frozen = UI.Switch(host, L("inspector.frozen"), false, function(v)
        local o = sel()
        if o then request("object.flag", { entryId = entryId, objectId = o.id, flag = "frozen", value = v }) end
    end)
    D.frozen:Dock(TOP)
    D.nograv = UI.Switch(host, L("inspector.no_gravity"), false, function(v)
        local o = sel()
        if o then request("object.flag", { entryId = entryId, objectId = o.id, flag = "nogravity", value = v }) end
    end)
    D.nograv:Dock(TOP)
    gap(D.nograv)

    local function row2(a, b)
        local p = vgui.Create("DPanel", host)
        p:Dock(TOP)
        p:SetTall(sc(32))
        p.Paint = function() end
        gap(p, 6)
        a:SetParent(p)
        b:SetParent(p)
        p.PerformLayout = function(_, w, h)
            local half = (w - sc(6)) / 2
            a:SetPos(0, 0) a:SetSize(half, h)
            b:SetPos(half + sc(6), 0) b:SetSize(half, h)
        end
        return p
    end
    local function pos() return Util.ToVector((sel() or {}).pos) end

    D.highlight = UI.Button(host, L("inspector.highlight"), function()
        local o = sel()
        if not o then return end
        local on = toggleHighlight(o)
        UI.Notify(on and L("inspector.highlight_on") or L("inspector.highlight_off"))
    end, { style = "warn", icon = "flag_yellow" })
    D.teleport = UI.Button(host, L("inspector.teleport"), function()
        local p = pos()
        if not p then return end
        RunConsoleCommand("rareload", "tp", p.x, p.y, p.z + 80)
        timer.Simple(0.4, function() RunConsoleCommand("rareload", "lookat", p.x, p.y, p.z) end)
    end, { style = "info", icon = "world_go" })
    D.row1 = row2(D.highlight, D.teleport)

    D.lookAt = UI.Button(host, L("inspector.look_at"), function()
        local p = pos()
        if p then RunConsoleCommand("rareload", "lookat", p.x, p.y, p.z) end
    end, { style = "info", icon = "eye" })
    D.copy = UI.Button(host, L("inspector.copy"), function()
        local o = sel()
        if not o then return end
        local m = DermaMenu()
        m:SetSkin("Rareload")
        local function add(label, value)
            m:AddOption(label, function()
                SetClipboardText(tostring(value or ""))
                UI.Notify(L("inspector.copied", label))
            end)
        end
        add(L("field.id"), o.id)
        add(L("field.class"), o.class)
        add(L("field.model"), o.model)
        add(L("field.position"), UI.Pos(o.pos))
        if o.maxHp then add(L("field.health"), (o.hp or 0) .. " / " .. o.maxHp) end
        if canManage() then
            m:AddOption("JSON", function()
                Inspector.waitingDef, Inspector.copyJson = o.id, true
                request("object.get", { entryId = entryId, objectId = o.id })
            end)
        end
        m:Open()
    end, { icon = "page_copy" })
    D.row2 = row2(D.lookAt, D.copy)

    D.edit = UI.Button(host, L("inspector.edit"), function()
        local o = sel()
        if not o then return end
        Inspector.waitingDef = o.id
        request("object.get", { entryId = entryId, objectId = o.id })
    end, { icon = "page_edit" })
    D.edit:Dock(TOP)
    gap(D.edit, 6)
    D.delete = UI.Button(host, L("inspector.delete"), function()
        local o = sel()
        if not o then return end
        UI.Confirm(L("inspector.delete"), L("inspector.delete_confirm", 1), function()
            request("object.delete", { entryId = entryId, objectId = o.id })
        end, L("inspector.delete"))
    end, { style = "danger", icon = "cross" })
    D.delete:Dock(TOP)

    D.empty = UI.Empty(host, "brick", L("inspector.select_hint"))
    D.empty:Dock(FILL)
    return D
end

local function updateDetail(D, o)
    local manage = canManage()
    for _, k in ipairs({ "model", "rows", "row1", "row2" }) do D[k]:SetVisible(o ~= nil) end
    for _, k in ipairs({ "frozen", "nograv", "edit", "delete" }) do D[k]:SetVisible(o ~= nil and manage) end
    D.empty:SetVisible(o == nil)
    if not o then return end
    D.model:ShowModel(o.model)
    D.frozen.value, D.nograv.value = o.frozen == true, o.nograv == true
    D.teleport:SetEnabled(RARELOAD.Can(LocalPlayer(), "rareload_teleport") and o.pos ~= nil)
    D.lookAt:SetEnabled(RARELOAD.Can(LocalPlayer(), "rareload_teleport") and o.pos ~= nil)
    local on = RARELOAD.Highlight.IsActive("saved", highlightId(o))
    D.highlight:SetLabel((on and "● " or "") .. L("inspector.highlight"))
end

-- Window --------------------------------------------------------------------------------------------

function Inspector.Open(entryId)
    if IsValid(Inspector.frame) then Inspector.frame:Remove() end
    local row = State.Row(entryId)
    local subtitle = row and (L("timeline.preview_title", entryId) .. "  ·  " .. UI.Date(row.time, "long")) or ""
    local frame = UI.Window({ title = L("inspector.title"), subtitle = subtitle, w = 1180, h = 740, overlay = true })
    Inspector.frame = frame
    local kind, sort, search, selectedId, shown = "all", "name", "", nil, {}
    local refresh

    frame:HeaderButton(L("timeline.refresh"), function() request("history.objects", { id = entryId }) end, { style = "info", icon = "arrow_refresh" })
    local deleteAll = frame:HeaderButton(L("inspector.delete_shown"), function()
        if #shown == 0 then return UI.Notify(L("inspector.nothing_shown"), "error") end
        UI.Confirm(L("inspector.delete_shown"), L("inspector.delete_confirm", #shown), function()
            for i, o in ipairs(shown) do   -- object requests are limited to 5 per second
                timer.Simple((i - 1) * 0.22, function() request("object.delete", { entryId = entryId, objectId = o.id }) end)
            end
        end, L("inspector.delete"))
    end, { style = "danger", icon = "bin" })
    deleteAll:SetVisible(canManage())

    local rail = vgui.Create("DPanel", frame)
    rail:Dock(LEFT)
    rail:SetWide(sc(210))
    rail:DockPadding(0, 0, sc(12), 0)
    rail.Paint = function(_, w, h)
        surface.SetDrawColor(C.line)
        surface.DrawLine(w - 1, 0, w - 1, h)
    end
    local searchBox = UI.Search(rail, L("inspector.search"), function(v)
        search = string.lower(v)
        refresh()
    end)
    searchBox:Dock(TOP)
    local sorts = {}
    for _, s in ipairs(SORTS) do sorts[#sorts + 1] = { id = s, label = L("inspector.sort." .. s) } end
    local sortBox = UI.Dropdown(rail, L("timeline.sort"), sorts, function() return sort end, function(s)
        sort = s
        refresh()
    end)
    sortBox:Dock(TOP)
    sortBox:DockMargin(0, sc(8), 0, sc(8))

    local counts = {}
    for _, k in ipairs(KINDS) do
        local b = vgui.Create("DButton", rail)
        b:SetText("")
        b:Dock(TOP)
        b:SetTall(sc(32))
        b:DockMargin(0, 0, 0, sc(4))
        b.Paint = function(self, w, h)
            local on = kind == k
            if on then
                draw.RoundedBox(sc(6), 0, 0, w, h, ColorAlpha(C.accent, 50))
                draw.RoundedBox(sc(3), 0, sc(7), sc(3), h - sc(14), C.accent)
            elseif self:IsHovered() then
                draw.RoundedBox(sc(6), 0, 0, w, h, C.surface)
            end
            draw.SimpleText(L("kind." .. k), "Rareload.Body", sc(14), h / 2, on and C.accentHi or C.text2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(tostring(counts[k] or 0), "Rareload.Small", w - sc(10), h / 2, C.text3, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        b.DoClick = function()
            kind = k
            refresh()
        end
    end
    local stat = UI.Label(rail, "", "Rareload.Small", C.text3)
    stat:Dock(BOTTOM)

    local detailHost = vgui.Create("DPanel", frame)
    detailHost:Dock(RIGHT)
    detailHost:SetWide(sc(310))
    detailHost:DockPadding(sc(12), 0, 0, 0)
    detailHost.Paint = function(_, _, h)
        surface.SetDrawColor(C.line)
        surface.DrawLine(0, 0, 0, h)
    end
    local detail = UI.Scroll(detailHost)
    detail:Dock(FILL)
    local D = buildDetail(detail, entryId, function()
        for _, o in ipairs(State.objects[entryId] or {}) do
            if o.id == selectedId then return o end
        end
    end)

    local scroll = UI.Scroll(frame)
    scroll:Dock(FILL)
    scroll:DockMargin(sc(12), 0, sc(12), 0)
    local grid = vgui.Create("DIconLayout", scroll)
    grid:Dock(FILL)
    grid:SetSpaceX(sc(10))
    grid:SetSpaceY(sc(10))

    local function select(id)
        selectedId = id
        local o
        for _, x in ipairs(State.objects[entryId] or {}) do if x.id == id then o = x end end
        updateDetail(D, o)
    end

    refresh = function()
        local all = State.objects[entryId] or {}
        counts = { all = #all }
        shown = {}
        for _, o in ipairs(all) do
            local k = isWeapon(o) and "weapons" or o.kind
            counts[k] = (counts[k] or 0) + 1
            local text = string.lower(UI.ObjectName(o.class, o.model) .. " " .. (o.class or "") .. " " .. (o.model or "") .. " " .. (o.id or ""))
            if (kind == "all" or kind == k or kind == o.kind) and (search == "" or string.find(text, search, 1, true)) then
                shown[#shown + 1] = o
            end
        end
        table.sort(shown, function(a, b)
            if sort == "distance" then return distanceTo(a) < distanceTo(b) end
            if sort == "health" then return (a.hp or 0) > (b.hp or 0) end
            return UI.ObjectName(a.class, a.model) < UI.ObjectName(b.class, b.model)
        end)
        grid:Clear()
        local isSelected = function(id) return id == selectedId end
        for i, o in ipairs(shown) do
            if i > MAX_CARDS then break end
            buildCard(grid, o, isSelected, select)
        end
        if #shown == 0 then
            local e = UI.Empty(grid, "brick", L("inspector.empty"), L("inspector.empty_hint"))
            e:SetSize(math.max(scroll:GetWide() - sc(24), sc(400)), sc(200))
        end
        grid:Layout()
        stat:SetText(#shown > MAX_CARDS and L("inspector.showing_first", MAX_CARDS, #shown) or L("inspector.showing", #shown))
        stat:SizeToContents()
        select(selectedId)
    end

    hook.Add("RareloadStateChanged", frame, function(_, what, id)
        if what == "objects" and id == entryId then refresh() end
    end)
    refresh()
    request("history.objects", { id = entryId })
end
