-- Client UI kit (REWRITE_PLAN.md §21.2, §25): translations, dates, palette, fonts and scale, the Derma
-- skin for stock controls, and the widgets every Rareload screen is built from (windows, buttons,
-- cards, chips, dropdowns, switches, sliders, rows, stat cards, dialogs), so they all look alike.
-- Also the toast and `rareload` client-command plumbing.

RARELOAD.UI = RARELOAD.UI or {}
local UI = RARELOAD.UI

-- Translations come from resource/localization/<lang>/rareload.properties (D16, G74).
function RARELOAD.L(key, ...)
    local phrase = language.GetPhrase("rareload." .. key)
    if select("#", ...) == 0 then return phrase end
    -- Translators write the format string, so a mismatched placeholder must not break the UI.
    local ok, text = pcall(string.format, phrase, ...)
    return ok and text or phrase
end
local L = RARELOAD.L

-- GMod reloads the .properties files itself; panels built with the old language rebuild on this hook.
cvars.AddChangeCallback("gmod_language", function()
    timer.Simple(0.1, function() hook.Run("RareloadLanguageChanged") end)
end, "Rareload.UI")

-- Palette -----------------------------------------------------------------------------------------

UI.C = {
    bg = Color(24, 26, 32, 250), bgDark = Color(18, 20, 25, 255), surface = Color(34, 37, 45), surfaceHi = Color(45, 49, 59),
    line = Color(58, 62, 74), text = Color(240, 242, 247), text2 = Color(170, 176, 190), text3 = Color(125, 131, 145),
    textOff = Color(92, 97, 110), accent = Color(65, 145, 255), accentHi = Color(120, 175, 255),
    ok = Color(70, 200, 120), warn = Color(255, 190, 80), bad = Color(240, 80, 80), info = Color(0, 190, 230),
    -- One colour per kind of thing, used in every screen.
    prop = Color(255, 150, 70), npc = Color(120, 215, 120), vehicle = Color(90, 170, 255), player = Color(180, 140, 255),
}
local C = UI.C

UI.KIND_COLORS = { entities = C.prop, npcs = C.npc, vehicles = C.vehicle, player = C.player }

function UI.Mix(a, b, t)
    t = math.Clamp(t, 0, 1)
    return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, (a.a or 255) + ((b.a or 255) - (a.a or 255)) * t)
end

function UI.HealthColor(hp, max)
    local f = (tonumber(max) or 0) > 0 and math.Clamp((tonumber(hp) or 0) / max, 0, 1) or 1
    return f < 0.5 and UI.Mix(C.bad, C.warn, f * 2) or UI.Mix(C.warn, C.ok, (f - 0.5) * 2)
end

-- Scale and fonts: a fixed set, recreated only when the screen size changes (G37) --------------------

function UI.sc(v) return math.floor(v * UI.S + 0.5) end
local sc = UI.sc

local clipCache, clipCount = {}, 0   -- UI.Clip results, below

local function createFonts()
    UI.S = math.Clamp(ScrH() / 1080, 0.85, 2)
    local function font(name, size, weight)
        surface.CreateFont(name, { font = "Roboto", size = math.floor(size * UI.S + 0.5), weight = weight, extended = true })
    end
    font("Rareload.Title", 25, 800)
    font("Rareload.Sub", 14, 500)
    font("Rareload.H1", 22, 700)
    font("Rareload.H2", 17, 600)
    font("Rareload.Body", 15, 500)
    font("Rareload.BodyB", 15, 700)
    font("Rareload.Small", 13, 500)
    font("Rareload.Tiny", 11, 700)
    font("Rareload.Stat", 26, 800)
    font("Rareload.Mono", 14, 500)
end
createFonts()
hook.Add("OnScreenSizeChanged", "Rareload.UI.Fonts", function()
    createFonts()
    clipCache, clipCount = {}, 0
end)

-- Fixed-size fonts for the tool screen and the world display, which don't depend on the screen.
surface.CreateFont("Rareload.Screen", { font = "Roboto", size = 22, weight = 600, extended = true })
surface.CreateFont("Rareload.ScreenTitle", { font = "Roboto", size = 38, weight = 900, extended = true })
surface.CreateFont("Rareload.Panel", { font = "Roboto", size = 24, weight = 500, extended = true })
surface.CreateFont("Rareload.PanelB", { font = "Roboto", size = 24, weight = 700, extended = true })
surface.CreateFont("Rareload.PanelTitle", { font = "Roboto", size = 32, weight = 800, extended = true })
surface.CreateFont("Rareload.PanelSmall", { font = "Roboto", size = 19, weight = 600, extended = true })
surface.CreateFont("Rareload.Label", { font = "Roboto", size = 19, weight = 700, extended = true })

-- Silk icons shipped with GMod.
local icons = {}
function UI.Icon(name)
    icons[name] = icons[name] or Material("icon16/" .. name .. ".png")
    return icons[name]
end

-- The icons are 16 px images: drawn at a whole multiple of 16 on whole pixels they stay sharp, so the
-- icon is snapped to that and centred in the `size` box asked for.
function UI.IconSize(size) return math.max(1, math.floor(size / 16 + 0.25)) * 16 end

function UI.DrawIcon(name, x, y, size, col)
    local s = UI.IconSize(size)
    surface.SetDrawColor(col or color_white)
    surface.SetMaterial(UI.Icon(name))
    surface.DrawTexturedRect(math.floor(x + (size - s) / 2 + 0.5), math.floor(y + (size - s) / 2 + 0.5), s, s)
end

-- A rounded label with a tinted background; returns its width.
function UI.DrawBadge(text, x, y, col, font, alignRight)
    font = font or "Rareload.Tiny"
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(text)
    local w, h = tw + sc(14), th + sc(6)
    if alignRight then x = x - w end
    draw.RoundedBox(sc(5), x, y, w, h, ColorAlpha(col, 45))
    draw.SimpleText(text, font, x + w / 2, y + h / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return w, h
end

-- Clips text to `maxW` pixels with an ellipsis.
-- Results are cached: panels clip the same texts every frame. The cache is emptied when it grows
-- large and when fonts change size.
function UI.Clip(text, font, maxW)
    text = tostring(text)
    maxW = math.floor(maxW)
    local key = font .. "\1" .. maxW .. "\1" .. text
    local hit = clipCache[key]
    if hit then return hit end
    if clipCount > 4000 then clipCache, clipCount = {}, 0 end

    local out = text
    surface.SetFont(font)
    if surface.GetTextSize(text) > maxW then
        while #out > 1 and surface.GetTextSize(out .. "…") > maxW do out = string.sub(out, 1, -2) end
        out = out .. "…"
    end
    clipCache[key], clipCount = out, clipCount + 1
    return out
end

-- Formatting --------------------------------------------------------------------------------------

function UI.Pos(t)
    local v = RARELOAD.Util.ToVector(t)
    return v and string.format("%.0f, %.0f, %.0f", v.x, v.y, v.z) or "-"
end

-- os.date only knows the C locale, so month and weekday names come from the translation files (G80).
local function fillDate(t, template)
    local d = os.date("*t", t)
    return (template:gsub("{(%w+)}", {
        wday = L("date.weekday." .. d.wday), month = L("date.month." .. d.month), mon = L("date.month_short." .. d.month),
        day = tostring(d.day), year = tostring(d.year), time = os.date("%H:%M:%S", t), hm = os.date("%H:%M", t),
    }))
end

-- style: "long" ("Tuesday 23 September 2026, 14:03:22") or "short" ("23 Sep 14:03").
function UI.Date(t, style)
    if not t then return "-" end
    return fillDate(t, L(style == "long" and "date.long" or "date.short"))
end

function UI.TimeAgo(t)
    local d = os.time() - (tonumber(t) or 0)
    if d < 45 then return L("time.just_now") end
    if d < 3600 then return L("time.minutes", math.floor(d / 60)) end
    if d < 86400 then return L("time.hours", math.floor(d / 3600)) end
    return L("time.days", math.floor(d / 86400))
end

-- Translated names of the states that are on.
local STATES = { "god", "notarget", "frozen", "noclip", "flashlight" }
function UI.States(states)
    local on = {}
    for _, k in ipairs(STATES) do
        if istable(states) and states[k] then on[#on + 1] = L("state." .. k) end
    end
    return #on > 0 and table.concat(on, ", ") or L("ui.none")
end

function UI.WeaponName(class)
    if not isstring(class) or class == "" then return L("ui.none") end
    local stored = weapons.GetStored(class)
    local name = stored and stored.PrintName or class
    return language.GetPhrase((string.gsub(name, "^#", "")))
end

-- A readable name for a saved object: the spawn menu's name of a vehicle, NPC or scripted entity,
-- the model's file name for a prop, else the class. Cached until the language changes.
local objectNames = {}
hook.Add("RareloadLanguageChanged", "Rareload.UI.ObjectNames", function() objectNames = {} end)

function UI.ObjectName(class, model)
    class = tostring(class or "?")
    local key = class .. "|" .. tostring(model)
    if objectNames[key] then return objectNames[key] end
    local name
    if string.StartsWith(class, "prop_") and not string.StartsWith(class, "prop_vehicle") then
        name = isstring(model) and string.StripExtension(string.GetFileFromFilename(model)) or nil
    else
        -- Vehicle entries are keyed by spawn name, not class; GetForEdit reads them without a copy (G67).
        for _, v in pairs(list.GetForEdit("Vehicles")) do
            if v.Class == class and (v.Model == model or not name) then name = v.Name end
        end
        local npc = list.GetEntry("NPC", class)
        local stored = scripted_ents.GetStored(class)
        name = name or (npc and npc.Name) or (stored and stored.t and stored.t.PrintName)
    end
    name = isstring(name) and name ~= "" and language.GetPhrase((string.gsub(name, "^#", ""))) or class
    objectNames[key] = name
    return name
end

-- util.IsValidModel is false for models the client hasn't loaded yet, so a mounted file counts too.
function UI.IsModel(model)
    return isstring(model) and model ~= "" and (util.IsValidModel(model) or file.Exists(model, "GAME"))
end

-- Derma skin: stock controls inside Rareload windows (text entries, scrollbars, menus, tooltips) --

local SKIN = { PrintName = "Rareload", Author = "Rareload", DermaVersion = 1 }

local function box(r, w, h, col) draw.RoundedBox(r, 0, 0, w, h, col) end

function SKIN:PaintPanel(panel, w, h)
    if panel.m_bBackground then box(6, w, h, panel.m_bgColor or C.surface) end
end

function SKIN:PaintTextEntry(panel, w, h)
    if panel.m_bBackground then
        box(sc(6), w, h, panel:HasFocus() and C.accent or C.line)
        draw.RoundedBox(sc(6), 1, 1, w - 2, h - 2, panel:IsEnabled() and C.surface or C.bgDark)
    end
    local placeholder = panel:GetPlaceholderText()
    if placeholder and placeholder ~= "" and panel:GetText() == "" and not panel:HasFocus() then
        local text = panel:GetText()
        panel:SetText(language.GetPhrase((placeholder:gsub("^#", ""))))
        panel:DrawTextEntryText(C.text3, C.accent, C.text)
        panel:SetText(text)
        return
    end
    panel:DrawTextEntryText(C.text, C.accent, C.text)
end

function SKIN:PaintVScrollBar() end
function SKIN:PaintScrollBarGrip(panel, w, h) draw.RoundedBox(sc(4), sc(1), 0, w - sc(2), h, panel.Hovered and C.text3 or C.line) end
function SKIN:PaintButtonUp() end
function SKIN:PaintButtonDown() end
function SKIN:PaintMenu(_, w, h) box(sc(4), w, h, C.surfaceHi) end
function SKIN:PaintMenuSpacer(_, w, h) box(0, w, h, C.line) end

function SKIN:PaintMenuOption(panel, w, h)
    if panel.Hovered or panel.Highlight then box(sc(4), w, h, ColorAlpha(C.accent, 90)) end
    if panel:GetChecked() then draw.RoundedBox(sc(3), sc(8), h / 2 - sc(3), sc(6), sc(6), C.accent) end
end

function SKIN:PaintTooltip(_, w, h) box(sc(4), w, h, C.surfaceHi) end

-- Colours Rareload sets itself; any other group is read from the Default skin when a panel asks for
-- it. The engine loads the Default skin after autorun files run, so nothing is copied here.
SKIN.Colours = setmetatable({
    Window = { TitleActive = C.text, TitleInactive = C.text2 },
    Label = { Default = C.text, Bright = C.text, Dark = C.text, Highlight = C.accent },
    Button = { Normal = C.text, Hover = C.text, Down = C.text2, Disabled = C.textOff },
    TooltipText = C.text,
}, { __index = function(_, k)
    local default = derma.GetNamedSkin("Default")
    return default and default.Colours[k]
end })
SKIN.colTextEntryText, SKIN.colTextEntryTextHighlight = C.text, C.accent
SKIN.colTextEntryTextCursor, SKIN.colTextEntryTextPlaceholder = C.text, C.text3

derma.DefineSkin("Rareload", "Rareload's dark skin", SKIN)

-- Widgets -----------------------------------------------------------------------------------------

local function hoverAnim(self, on)
    self.anim = Lerp(FrameTime() * 12, self.anim or 0, on and 1 or 0)
    return self.anim
end

-- style: "primary" (default), "success", "danger", "warn", "info" or "ghost". `solid` fills the button.
local STYLES = { primary = C.accent, success = C.ok, danger = C.bad, warn = C.warn, info = C.info, ghost = C.text3 }

function UI.Button(parent, text, onClick, opts)
    opts = opts or {}
    local col = STYLES[opts.style or "primary"]
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(sc(opts.tall or 32))
    b.label, b.icon = text, opts.icon
    function b:SetLabel(t) self.label = t end
    -- An active toggle button is drawn solid with a pulsing dot.
    function b:SetActive(on) self.active = on end
    b.Paint = function(self, w, h)
        local a = self:IsEnabled() and hoverAnim(self, self:IsHovered()) or 0
        local fill, textCol
        if not self:IsEnabled() then
            fill, textCol = C.bgDark, C.textOff
        elseif opts.solid or self.active then
            fill, textCol = UI.Mix(col, color_white, a * 0.15), Color(15, 17, 22)
        else
            fill, textCol = UI.Mix(UI.Mix(C.surface, col, 0.14), col, a * 0.55), UI.Mix(C.text, color_white, a)
        end
        if self.Depressed then fill = UI.Mix(fill, color_black, 0.15) end
        box(sc(7), w, h, fill)
        surface.SetFont("Rareload.BodyB")
        local tw = surface.GetTextSize(self.label)
        local is = UI.IconSize(sc(16))
        local iw = self.icon and is + (self.label ~= "" and sc(7) or 0) or 0   -- no gap on an icon-only button
        local x = math.floor((w - tw - iw) / 2)
        if self.icon then UI.DrawIcon(self.icon, x, math.floor((h - is) / 2), is, self:IsEnabled() and color_white or C.textOff) end
        draw.SimpleText(self.label, "Rareload.BodyB", x + iw, math.floor(h / 2), textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if self.active then
            local r = sc(3) + sc(1.5) * math.abs(math.sin(RealTime() * 4))
            draw.RoundedBox(r, sc(12) - r, h / 2 - r, r * 2, r * 2, textCol)
        end
    end
    b.DoClick = function(self)
        surface.PlaySound("ui/buttonclickrelease.wav")
        if onClick then onClick(self) end
    end
    function b:SizeToLabel(pad)
        surface.SetFont("Rareload.BodyB")
        self:SetWide(surface.GetTextSize(self.label) + (self.icon and UI.IconSize(sc(16)) + (self.label ~= "" and sc(7) or 0) or 0) + sc(pad or 28))
    end
    return b
end

-- A rounded card. `paint(self, w, h)` draws its content after the background.
function UI.Card(parent, paint, col)
    local p = vgui.Create("DPanel", parent)
    p.Paint = function(self, w, h)
        box(sc(10), w, h, col or C.surface)
        if paint then paint(self, w, h) end
    end
    return p
end

function UI.Label(parent, text, font, col)
    local l = vgui.Create("DLabel", parent)
    l:SetFont(font or "Rareload.Body")
    l:SetTextColor(col or C.text)
    l:SetText(text)
    l:SizeToContents()
    return l
end

-- A text entry with a search icon and a placeholder. onChange(text) runs on every keystroke.
function UI.Search(parent, placeholder, onChange)
    local e = vgui.Create("DTextEntry", parent)
    e:SetTall(sc(32))
    e:SetFont("Rareload.Body")
    e:SetUpdateOnType(true)
    e:SetTextInset(sc(28), 0)
    e.Paint = function(self, w, h)
        box(sc(8), w, h, self:HasFocus() and C.surfaceHi or C.surface)
        UI.DrawIcon("magnifier", sc(8), (h - sc(16)) / 2, sc(16), ColorAlpha(color_white, 160))
        self:DrawTextEntryText(C.text, C.accent, C.text)
        if self:GetValue() == "" then
            draw.SimpleText(placeholder, "Rareload.Body", sc(30), h / 2, C.text3, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    e.OnValueChange = function(_, v) onChange(v) end
    return e
end

-- A multi-line or single-line text entry in the kit's style.
function UI.TextEntry(parent, placeholder, multiline)
    local e = vgui.Create("DTextEntry", parent)
    e:SetFont(multiline and "Rareload.Mono" or "Rareload.Body")
    e:SetMultiline(multiline or false)
    e:SetTall(sc(32))
    e.Paint = function(self, w, h)
        box(sc(8), w, h, self:HasFocus() and C.surfaceHi or C.surface)
        self:DrawTextEntryText(C.text, C.accent, C.text)
        if placeholder and self:GetValue() == "" and not self:HasFocus() then
            draw.SimpleText(placeholder, "Rareload.Body", sc(8), multiline and sc(10) or h / 2, C.text3, TEXT_ALIGN_LEFT,
                multiline and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
        end
    end
    return e
end

-- Equal-width segmented choices. items = { { id, label } }. Returns the panel; :SetSelected(id).
function UI.Chips(parent, items, selected, onSelect)
    local p = vgui.Create("DPanel", parent)
    p:SetTall(sc(28))
    p.Paint = function() end
    p.selected = selected
    local buttons = {}
    for _, item in ipairs(items) do
        local b = vgui.Create("DButton", p)
        b:SetText("")
        b.Paint = function(self, w, h)
            local on = p.selected == item.id
            local a = hoverAnim(self, self:IsHovered())
            box(sc(6), w, h, on and ColorAlpha(C.accent, 90) or UI.Mix(C.surface, C.surfaceHi, a))
            draw.SimpleText(UI.Clip(item.label, "Rareload.Small", w - sc(6)), "Rareload.Small", w / 2, h / 2,
                on and C.text or C.text2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        b.DoClick = function()
            p.selected = item.id
            onSelect(item.id)
        end
        buttons[#buttons + 1] = b
    end
    p.PerformLayout = function(_, w, h)
        local gap = sc(5)
        local bw = math.floor((w - gap * (#buttons - 1)) / #buttons)
        for i, b in ipairs(buttons) do
            b:SetPos((i - 1) * (bw + gap), 0)
            b:SetSize(i == #buttons and w - (i - 1) * (bw + gap) or bw, h)
        end
    end
    function p:SetSelected(id) self.selected = id end
    return p
end

-- A button that opens a menu of options. options = { { id, label } }; get() returns the current id.
function UI.Dropdown(parent, prefix, options, get, onSelect)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(sc(28))
    b.Paint = function(self, w, h)
        local a = hoverAnim(self, self:IsHovered())
        box(sc(6), w, h, UI.Mix(C.surface, C.surfaceHi, a))
        local current = get()
        local label
        for _, o in ipairs(options) do if o.id == current then label = o.label end end
        draw.RoundedBox(sc(3), sc(10), h / 2 - sc(3), sc(6), sc(6), C.accent)
        draw.SimpleText(UI.Clip((prefix and prefix .. " " or "") .. (label or "?"), "Rareload.Small", w - sc(44)),
            "Rareload.Small", sc(22), h / 2, C.text2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(C.text3)
        draw.NoTexture()
        local x, y = w - sc(14), h / 2
        surface.DrawPoly({ { x = x - sc(4), y = y - sc(2) }, { x = x + sc(4), y = y - sc(2) }, { x = x, y = y + sc(3) } })
    end
    b.DoClick = function()
        local m = DermaMenu()
        m:SetSkin("Rareload")
        for _, o in ipairs(options) do
            local opt = m:AddOption(o.label, function() onSelect(o.id) end)
            opt:SetChecked(o.id == get())
            opt:SetTextColor(C.text)
        end
        m:Open()
    end
    return b
end

-- A checkbox with a label. value(): current state; onChange(new state).
function UI.Check(parent, label, value, onChange)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(sc(24))
    b.value = value
    surface.SetFont("Rareload.Small")
    b:SetWide(surface.GetTextSize(label) + sc(30))
    b.Paint = function(self, w, h)
        local s = sc(16)
        local y = (h - s) / 2
        draw.RoundedBox(sc(4), 0, y, s, s, self.value and C.accent or (self:IsHovered() and C.surfaceHi or C.line))
        if self.value then
            surface.SetDrawColor(color_white)
            surface.DrawLine(sc(4), y + s / 2, sc(7), y + s - sc(4))
            surface.DrawLine(sc(7), y + s - sc(4), s - sc(3), y + sc(4))
        end
        draw.SimpleText(label, "Rareload.Small", s + sc(8), h / 2, self:IsEnabled() and C.text2 or C.textOff, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function(self)
        self.value = not self.value
        onChange(self.value)
    end
    function b:SetValue(v) self.value = v end
    return b
end

-- A setting row with a toggle switch. opts = { tooltip, disabled, note } (note: small right text).
function UI.Switch(parent, label, value, onChange, opts)
    opts = opts or {}
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(sc(30))
    b.value = value
    b.knob = value and 1 or 0
    if opts.tooltip then b:SetTooltip(opts.tooltip) end
    b:SetEnabled(not opts.disabled)
    b.Paint = function(self, w, h)
        self.knob = Lerp(FrameTime() * 14, self.knob, self.value and 1 or 0)
        local a = self:IsEnabled() and hoverAnim(self, self:IsHovered()) or 0
        if a > 0.01 then box(sc(6), w, h, ColorAlpha(C.surfaceHi, 200 * a)) end
        local sw, sh = sc(34), sc(18)
        local sx, sy = w - sw - sc(8), (h - sh) / 2
        local on = self:IsEnabled() and C.ok or C.textOff
        draw.RoundedBox(sh / 2, sx, sy, sw, sh, UI.Mix(C.line, on, self.knob))
        draw.RoundedBox(sh / 2, sx + sc(2) + (sw - sh) * self.knob, sy + sc(2), sh - sc(4), sh - sc(4), color_white)
        local textCol = self:IsEnabled() and C.text or C.textOff
        local right = sx - sc(8)
        if opts.note then
            surface.SetFont("Rareload.Tiny")
            right = right - surface.GetTextSize(opts.note) - sc(6)
            draw.SimpleText(opts.note, "Rareload.Tiny", sx - sc(8), h / 2, C.text3, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText(UI.Clip(label, "Rareload.Body", right - sc(8)), "Rareload.Body", sc(8), h / 2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function(self)
        self.value = not self.value
        surface.PlaySound("ui/buttonclick.wav")
        onChange(self.value)
    end
    return b
end

-- A compact slider row. Sends the value once dragging stops.
function UI.Slider(parent, label, value, min, max, decimals, suffix, onChange, opts)
    opts = opts or {}
    local p = vgui.Create("DButton", parent)
    p:SetText("")
    p:SetTall(sc(44))
    p.value = value
    if opts.tooltip then p:SetTooltip(opts.tooltip) end
    p:SetEnabled(not opts.disabled)
    local function fmt(v) return string.format("%." .. decimals .. "f", v) .. (suffix or "") end
    local function track(w) return sc(8), w - sc(16) end
    p.Paint = function(self, w, h)
        local textCol = self:IsEnabled() and C.text or C.textOff
        draw.SimpleText(UI.Clip(label, "Rareload.Body", w - sc(90)), "Rareload.Body", sc(8), sc(12), textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(fmt(self.value) .. (opts.note and "  " .. opts.note or ""), "Rareload.Small", w - sc(8), sc(12),
            self.dragging and C.accentHi or C.text2, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        local x, tw = track(w)
        local f = (self.value - min) / (max - min)
        local y = h - sc(13)
        draw.RoundedBox(sc(3), x, y - sc(3), tw, sc(6), C.line)
        draw.RoundedBox(sc(3), x, y - sc(3), tw * f, sc(6), self:IsEnabled() and C.accent or C.textOff)
        draw.RoundedBox(sc(7), x + tw * f - sc(7), y - sc(7), sc(14), sc(14), color_white)
    end
    local function setFromMouse(self)
        local x, tw = track(self:GetWide())
        local mx = self:ScreenToLocal(gui.MouseX(), 0)
        local v = min + math.Clamp((mx - x) / tw, 0, 1) * (max - min)
        self.value = math.Round(v, decimals)
    end
    p.OnMousePressed = function(self, code)
        if code == MOUSE_RIGHT and self.DoRightClick then return self:DoRightClick() end
        if code ~= MOUSE_LEFT or not self:IsEnabled() then return end
        self.dragging = true
        self:MouseCapture(true)
        setFromMouse(self)
    end
    p.OnMouseReleased = function(self)
        if not self.dragging then return end
        self.dragging = false
        self:MouseCapture(false)
        onChange(self.value)
    end
    p.Think = function(self)
        if self.dragging then setFromMouse(self) end
    end
    return p
end

-- Label/value rows with dividers. rows() returns { { label, value, color? } }; height follows the rows.
function UI.Rows(parent, rows)
    local p = vgui.Create("DPanel", parent)
    local rh = sc(24)
    p.Paint = function(self, w, h)
        box(sc(10), w, h, C.surface)
        local list = rows()
        local y = sc(6)
        for i, r in ipairs(list) do
            if i > 1 then
                surface.SetDrawColor(ColorAlpha(C.line, 120))
                surface.DrawLine(sc(12), y, w - sc(12), y)
            end
            draw.SimpleText(r[1], "Rareload.Small", sc(12), y + rh / 2, C.text3, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            surface.SetFont("Rareload.Small")
            local lw = surface.GetTextSize(r[1])
            draw.SimpleText(UI.Clip(r[2], "Rareload.Small", w - lw - sc(40)), "Rareload.Small", w - sc(12), y + rh / 2,
                r[3] or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            y = y + rh
        end
        local want = #list * rh + sc(12)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    return p
end

-- A row of stat cards. cards() returns { { label, value (nil = not saved), color } }.
function UI.Stats(parent, cards)
    local p = vgui.Create("DPanel", parent)
    p:SetTall(sc(64))
    p.Paint = function(_, w, h)
        local list = cards()
        local gap = sc(7)
        local cw = (w - gap * (#list - 1)) / #list
        for i, c in ipairs(list) do
            local x = (i - 1) * (cw + gap)
            draw.RoundedBox(sc(8), x, 0, cw, h, C.surface)
            if c[2] ~= nil then
                draw.SimpleText(tostring(c[2]), "Rareload.Stat", x + cw / 2, h * 0.42, c[3] or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(L("ui.not_saved"), "Rareload.Small", x + cw / 2, h * 0.42, C.textOff, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            draw.SimpleText(string.upper(c[1]), "Rareload.Tiny", x + cw / 2, h * 0.8, C.text3, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    return p
end

-- A centered icon, title and hint for empty lists and "select something" panes.
function UI.Empty(parent, icon, title, hint)
    local p = vgui.Create("DPanel", parent)
    p:SetMouseInputEnabled(false)
    p.Paint = function(_, w, h)
        UI.DrawIcon(icon, w / 2 - sc(16), h / 2 - sc(46), sc(32), ColorAlpha(color_white, 90))
        draw.SimpleText(title, "Rareload.H2", w / 2, h / 2 + sc(4), C.text2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if hint then draw.SimpleText(hint, "Rareload.Small", w / 2, h / 2 + sc(28), C.text3, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
    end
    return p
end

-- A model preview that frames its model and turns slowly.
function UI.Model(parent, model, speed)
    local mp = vgui.Create("DModelPanel", parent)
    mp:SetMouseInputEnabled(false)
    function mp:ShowModel(m)
        m = UI.IsModel(m) and m or "models/error.mdl"
        if self.shown == m then return end
        self.shown = m
        self:SetModel(m)
        local ent = self:GetEntity()
        if not IsValid(ent) then return end
        local mn, mx = ent:GetRenderBounds()
        local center, size = (mn + mx) * 0.5, math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z, 1)
        local dist = size * 1.25 / math.tan(math.rad(21))
        self:SetLookAt(center)
        self:SetCamPos(center + Vector(dist * 0.65, dist * 0.5, dist * 0.35))
        self:SetFOV(42)
    end
    mp.LayoutEntity = function(_, ent) ent:SetAngles(Angle(0, RealTime() * (speed or 22) % 360, 0)) end
    mp:ShowModel(model)
    return mp
end

-- Scrollbar in the kit's style.
function UI.Scroll(parent)
    local s = vgui.Create("DScrollPanel", parent)
    s:SetSkin("Rareload")
    s:GetVBar():SetWide(sc(8))
    return s
end

-- Windows -----------------------------------------------------------------------------------------

-- opts = { title, subtitle, w, h, overlay? (dims the screen; a click outside closes) }.
-- Returns the frame; frame.body is the content area and frame:HeaderButton(text, fn, opts) adds a
-- button to the header, right to left.
function UI.Window(opts)
    local headH = sc(62)
    local backdrop
    if opts.overlay then
        backdrop = vgui.Create("DPanel")
        backdrop:SetSize(ScrW(), ScrH())
        backdrop:MakePopup()
        backdrop.Paint = function(_, w, h)
            surface.SetDrawColor(0, 0, 0, 170)
            surface.DrawRect(0, 0, w, h)
        end
    end

    local frame = vgui.Create("DFrame")
    frame:SetSkin("Rareload")
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetSize(math.min(sc(opts.w), ScrW() * 0.95), math.min(sc(opts.h), ScrH() * 0.92))
    frame:SetMinWidth(math.min(sc(opts.w * 0.7), ScrW() * 0.95))
    frame:SetMinHeight(math.min(sc(opts.h * 0.7), ScrH() * 0.92))
    frame:SetSizable(true)
    frame:Center()
    frame:MakePopup()
    frame:DockPadding(sc(12), headH + sc(10), sc(12), sc(12))
    frame.title, frame.subtitle = opts.title, opts.subtitle

    frame.Paint = function(self, w, h)
        box(sc(14), w, h, C.bg)
        draw.SimpleText(self.title, "Rareload.Title", sc(18), sc(12), C.accentHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if self.subtitle then draw.SimpleText(self.subtitle, "Rareload.Sub", sc(20), sc(40), C.text3, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP) end
        surface.SetDrawColor(C.line)
        surface.DrawLine(0, headH, w, headH)
    end

    -- Drag from anywhere in the header, not only the top 24 pixels.
    frame.OnMousePressed = function(self)
        local x, y = self:ScreenToLocal(gui.MouseX(), gui.MouseY())
        if self:GetSizable() and x > self:GetWide() - sc(20) and y > self:GetTall() - sc(20) then
            self.Sizing = { gui.MouseX() - self:GetWide(), gui.MouseY() - self:GetTall() }
            self:MouseCapture(true)
        elseif y < headH then
            self.Dragging = { gui.MouseX() - self.x, gui.MouseY() - self.y }
            self:MouseCapture(true)
        end
    end

    local buttons = {}
    function frame:HeaderButton(text, fn, bopts)
        local b = UI.Button(self, text, fn, bopts)
        b:SizeToLabel(bopts and bopts.pad)
        buttons[#buttons + 1] = b
        self:InvalidateLayout()
        return b
    end
    frame:HeaderButton("", function() frame:Close() end, { style = "danger", icon = "cross", pad = 4 })

    local baseLayout = frame.PerformLayout
    frame.PerformLayout = function(self, w, h)
        if baseLayout then baseLayout(self, w, h) end
        local x = w - sc(14)
        for _, b in ipairs(buttons) do
            if b:IsVisible() then
                x = x - b:GetWide()
                b:SetPos(x, (headH - b:GetTall()) / 2)
                x = x - sc(6)
            end
        end
    end

    frame.OnRemove = function()
        if IsValid(backdrop) then backdrop:Remove() end
    end
    if backdrop then
        backdrop.OnMousePressed = function() if IsValid(frame) then frame:Close() end end
    end
    return frame
end

-- A themed yes/no dialog above everything else.
function UI.Confirm(title, body, onYes, yesLabel)
    local d = UI.Window({ title = title, w = 460, h = 190, overlay = true })
    d:SetSizable(false)
    local text = UI.Label(d, body, "Rareload.Body", C.text2)
    text:Dock(TOP)
    text:SetWrap(true)
    text:SetAutoStretchVertical(true)
    local row = vgui.Create("DPanel", d)
    row:Dock(BOTTOM)
    row:SetTall(sc(34))
    row.Paint = function() end
    local no = UI.Button(row, L("ui.cancel"), function() d:Close() end, { style = "ghost" })
    no:Dock(RIGHT)
    no:SizeToLabel()
    local yes = UI.Button(row, yesLabel or L("ui.confirm"), function()
        d:Close()
        onYes()
    end, { style = "danger", solid = true })
    yes:Dock(RIGHT)
    yes:DockMargin(0, 0, sc(8), 0)
    yes:SizeToLabel()
    return d
end

function UI.Notify(text, kind)
    notification.AddLegacy(text, kind == "error" and NOTIFY_ERROR or NOTIFY_GENERIC, 3)   -- G79
end

-- Toasts ------------------------------------------------------------------------------------------

local KINDS = { info = NOTIFY_GENERIC, ok = NOTIFY_GENERIC, error = NOTIFY_ERROR, hint = NOTIFY_HINT }

RARELOAD.Net.On("toast", function(t)
    notification.AddLegacy(L(t.key, unpack(t.args or {})), KINDS[t.kind] or NOTIFY_GENERIC, 4)
    surface.PlaySound(t.kind == "error" and "buttons/button10.wav" or "buttons/button14.wav")
    hook.Run("RareloadToast", t)
end)

RARELOAD.Net.On("dev.reload", function()
    include("autorun/rareload.lua")
end)

-- Client subcommands of `rareload` (timeline, menu…): the server owns the command and sends them here.
UI.commands = UI.commands or {}   -- name -> fn(args)

function UI.Command(name, fn)
    UI.commands[name] = fn
end

RARELOAD.Net.On("cmd", function(p)
    local fn = UI.commands[p.name]
    if fn then fn(p.args or {}) end
end)

-- The click that respawns a player is still held when Rareload hands their weapons back, and must not
-- fire them (the camera would take a screenshot, the tool gun would save). Attacks are ignored after a
-- respawn until both buttons are released, for at most 3 seconds.
local wasAlive, blockUntil = true, 0
hook.Add("CreateMove", "Rareload.RespawnClick", function(cmd)
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local alive = lp:Alive()
    if alive and not wasAlive and RARELOAD.Get(lp, "enabled") then blockUntil = RealTime() + 3 end
    wasAlive = alive
    if RealTime() > blockUntil then return end
    if not cmd:KeyDown(IN_ATTACK) and not cmd:KeyDown(IN_ATTACK2) then
        blockUntil = 0
        return
    end
    cmd:RemoveKey(IN_ATTACK)
    cmd:RemoveKey(IN_ATTACK2)
end)
