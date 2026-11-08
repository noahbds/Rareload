-- Client UI kit: translations, dates, palette, fonts and scale, the Derma
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
    bg = Color(24, 26, 32, 250),
    bgDark = Color(18, 20, 25, 255),
    surface = Color(34, 37, 45),
    surfaceHi = Color(45, 49, 59),
    line = Color(58, 62, 74),
    text = Color(240, 242, 247),
    text2 = Color(170, 176, 190),
    text3 = Color(125, 131, 145),
    textOff = Color(92, 97, 110),
    accent = Color(65, 145, 255),
    accentHi = Color(120, 175, 255),
    ok = Color(70, 200, 120),
    warn = Color(255, 190, 80),
    bad = Color(240, 80, 80),
    info = Color(0, 190, 230),
    -- One colour per kind of thing, used in every screen.
    prop = Color(255, 150, 70),
    npc = Color(120, 215, 120),
    vehicle = Color(90, 170, 255),
    player = Color(180, 140, 255),
}
local C = UI.C

UI.KIND_COLORS = { entities = C.prop, npcs = C.npc, vehicles = C.vehicle, player = C.player }

-- A blend of two colours. At either end it is that colour itself (no new Color for the many widgets
-- that are not hovered or animating): treat the result as read-only.
function UI.Mix(fromColor, toColor, fraction)
    if fraction <= 0 then return fromColor end
    if fraction >= 1 then return toColor end
    return Color(fromColor.r + (toColor.r - fromColor.r) * fraction,
        fromColor.g + (toColor.g - fromColor.g) * fraction, fromColor.b + (toColor.b - fromColor.b) * fraction,
        (fromColor.a or 255) + ((toColor.a or 255) - (fromColor.a or 255)) * fraction)
end

function UI.HealthColor(hp, max)
    local fraction = (tonumber(max) or 0) > 0 and math.Clamp((tonumber(hp) or 0) / max, 0, 1) or 1
    return fraction < 0.5 and UI.Mix(C.bad, C.warn, fraction * 2) or UI.Mix(C.warn, C.ok, (fraction - 0.5) * 2)
end

-- Scale and fonts: a fixed set, recreated only when the screen size changes (G37) --------------------

function UI.sc(value) return math.floor(value * UI.S + 0.5) end

local sc = UI.sc

local clipCache, clipCount = {}, 0 -- UI.Clip results, below

-- Every Rareload font: name = { size, weight }. Window fonts follow the screen size; the tool screen,
-- the world display and the spawn menu (not scaled) keep theirs. No shadows: they blur small text.
local SCALED_FONTS = {
    ["Rareload.Title"] = { 25, 800 }, ["Rareload.Sub"] = { 14, 500 }, ["Rareload.H1"] = { 22, 700 },
    ["Rareload.H2"] = { 17, 600 }, ["Rareload.Body"] = { 15, 500 }, ["Rareload.BodyB"] = { 15, 700 },
    ["Rareload.Small"] = { 13, 500 }, ["Rareload.Tiny"] = { 11, 700 }, ["Rareload.Stat"] = { 26, 800 },
    ["Rareload.Mono"] = { 14, 500 },
}
local FIXED_FONTS = {
    -- The tool screen (cl_toolscreen.lua): 256 px shown a few centimetres wide, so nothing under 21 px.
    ["Rareload.Screen"] = { 26, 800 }, ["Rareload.ScreenSmall"] = { 21, 800 }, ["Rareload.ScreenHead"] = { 27, 900 },
    ["Rareload.ScreenBig"] = { 50, 900 },
    ["Rareload.Panel"] = { 24, 500 }, ["Rareload.PanelB"] = { 24, 700 }, ["Rareload.PanelTitle"] = { 32, 800 },
    ["Rareload.PanelSmall"] = { 19, 600 }, ["Rareload.Label"] = { 19, 700 },
    ["Rareload.Menu.Title"] = { 26, 800 }, ["Rareload.Menu.Head"] = { 17, 700 }, ["Rareload.Menu.Row"] = { 16, 500 },
    ["Rareload.Menu.Value"] = { 16, 700 }, ["Rareload.Menu.Note"] = { 13, 500 },
}

local function font(name, size, weight)
    surface.CreateFont(name, { font = "Roboto", size = size, weight = weight, extended = true })
end

local function createFonts()
    UI.S = math.Clamp(ScrH() / 1080, 0.85, 2)
    for name, spec in pairs(SCALED_FONTS) do font(name, math.floor(spec[1] * UI.S + 0.5), spec[2]) end
end
createFonts()
for name, spec in pairs(FIXED_FONTS) do font(name, spec[1], spec[2]) end
hook.Add("OnScreenSizeChanged", "Rareload.UI.Fonts", function()
    createFonts()
    clipCache, clipCount = {}, 0
end)

-- Silk icons shipped with GMod.
local icons = {}
function UI.Icon(name)
    icons[name] = icons[name] or Material("icon16/" .. name .. ".png")
    return icons[name]
end

-- The icons are 16 px images: drawn at a whole multiple of 16 on whole pixels they stay sharp, so the
-- icon is snapped to that and centred in the `size` box asked for.
function UI.IconSize(size) return math.max(1, math.floor(size / 16 + 0.25)) * 16 end

function UI.DrawIcon(name, posX, posY, size, col)
    local iconSize = UI.IconSize(size)
    surface.SetDrawColor(col or color_white)
    surface.SetMaterial(UI.Icon(name))
    surface.DrawTexturedRect(math.floor(posX + (size - iconSize) / 2 + 0.5),
        math.floor(posY + (size - iconSize) / 2 + 0.5), iconSize, iconSize)
end

-- World markers (checkpoints, the death spot): a beam standing on `pos`, and above it on screen a
-- tag with an icon, a text and the distance. alpha 0-255 fades the whole marker. They run every frame,
-- so they reuse these instead of making new colours and vectors.
local markTop, markBg, markIcon, markText, markDist = Vector(), Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0),
    Color(0, 0, 0)

local function tint(out, col, alpha)
    out.r, out.g, out.b, out.a = col.r, col.g, col.b, alpha
    return out
end

-- Inside PostDrawTranslucentRenderables, after render.SetColorMaterial().
function UI.DrawWorldBeam(pos, height, width, col, alpha)
    markTop:Set(pos)
    markTop.z = markTop.z + height
    render.DrawBeam(pos, markTop, width, 0, 1, tint(markBg, col, alpha))
end

-- Inside HUDPaint. `distance` is shown under the tag.
function UI.DrawWorldTag(pos, height, icon, text, textCol, distance, alpha)
    markTop:Set(pos)
    markTop.z = markTop.z + height
    local screen = markTop:ToScreen()
    if not screen.visible then return end
    surface.SetFont("Rareload.BodyB")
    local tw, th = surface.GetTextSize(text)
    local tagWidth, tagHeight = tw + sc(34), th + sc(10)
    local posX, posY = math.floor(screen.x - tagWidth / 2), math.floor(screen.y - tagHeight)
    draw.RoundedBox(sc(6), posX, posY, tagWidth, tagHeight, tint(markBg, C.surface, alpha * 0.86))
    UI.DrawIcon(icon, posX + sc(6), posY + (tagHeight - sc(16)) / 2, sc(16), tint(markIcon, color_white, alpha))
    draw.SimpleText(text, "Rareload.BodyB", posX + sc(28), posY + tagHeight / 2, tint(markText, textCol, alpha),
        TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(L("inspector.units", math.Round(distance)), "Rareload.Small", screen.x, posY + tagHeight + sc(2),
        tint(markDist, C.text3, alpha), TEXT_ALIGN_CENTER)
end

-- A rounded label with a tinted background; returns its width.
function UI.DrawBadge(text, posX, posY, col, font, alignRight)
    font = font or "Rareload.Tiny"
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(text)
    local width, height = tw + sc(14), th + sc(6)
    if alignRight then posX = posX - width end
    draw.RoundedBox(sc(5), posX, posY, width, height, ColorAlpha(col, 45))
    draw.SimpleText(text, font, posX + width / 2, posY + height / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return width, height
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

function UI.Pos(value)
    local vec = RARELOAD.Util.ToVector(value)
    return vec and string.format("%.0f, %.0f, %.0f", vec.x, vec.y, vec.z) or "-"
end

-- os.date only knows the C locale, so month and weekday names come from the translation files (G80).
local function fillDate(time, template)
    local date = os.date("*t", time)
    return (template:gsub("{(%w+)}", {
        wday = L("date.weekday." .. date.wday), month = L("date.month." .. date.month),
        mon = L("date.month_short." .. date.month),
        day = tostring(date.day), year = tostring(date.year), time = os.date("%H:%M:%S", time),
            hm = os.date("%H:%M", time),
    }))
end

-- style: "long" ("Tuesday 23 September 2026, 14:03:22") or "short" ("23 Sep 14:03").
function UI.Date(time, style)
    if not time then return "-" end
    return fillDate(time, L(style == "long" and "date.long" or "date.short"))
end

function UI.TimeAgo(time)
    local age = os.time() - (tonumber(time) or 0)
    if age < 45 then return L("time.just_now") end
    if age < 3600 then return L("time.minutes", math.floor(age / 60)) end
    if age < 86400 then return L("time.hours", math.floor(age / 3600)) end
    local days = math.floor(age / 86400)
    return days == 1 and L("time.day") or L("time.days", days)
end

-- Translated names of the states that are on.
function UI.States(states)
    local on = {}
    for _, stateName in ipairs(RARELOAD.PLAYER_STATES) do
        if istable(states) and states[stateName] then on[#on + 1] = L("state." .. stateName) end
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
        for _, vehicle in pairs(list.GetForEdit("Vehicles")) do
            if vehicle.Class == class and (vehicle.Model == model or not name) then name = vehicle.Name end
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
-- What a saved object is called on screen: the player's own name for it, or its automatic one. Its
-- number follows only when another object of the same save has that name (see UI.LabelObjects).
function UI.ObjectLabel(object)
    local name = object.name or UI.ObjectName(object.class, object.model)
    return object.shared and object.num and name .. " #" .. object.num or name
end

-- Marks the objects of one save whose name another of them shares.
function UI.LabelObjects(objects)
    local count = {}
    for _, object in ipairs(objects) do
        local name = object.name or UI.ObjectName(object.class, object.model)
        count[name] = (count[name] or 0) + 1
    end
    for _, object in ipairs(objects) do object.shared = count[object.name or UI.ObjectName(object.class,
        object.model)] > 1 end
end

function UI.IsModel(model)
    return isstring(model) and model ~= "" and (util.IsValidModel(model) or file.Exists(model, "GAME"))
end

-- Derma skin: stock controls inside Rareload windows (text entries, scrollbars, menus, tooltips) --

local SKIN = { PrintName = "Rareload", Author = "Rareload", DermaVersion = 1 }

local function box(radius, width, height, col) draw.RoundedBox(radius, 0, 0, width, height, col) end

function SKIN:PaintPanel(panel, width, height)
    if panel.m_bBackground then box(6, width, height, panel.m_bgColor or C.surface) end
end

function SKIN:PaintTextEntry(panel, width, height)
    if panel.m_bBackground then
        box(sc(6), width, height, panel:HasFocus() and C.accent or C.line)
        draw.RoundedBox(sc(6), 1, 1, width - 2, height - 2, panel:IsEnabled() and C.surface or C.bgDark)
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

function SKIN:PaintScrollBarGrip(panel, width, height)
    draw.RoundedBox(sc(4), sc(1), 0, width - sc(2), height,
        panel.Hovered and C.text3 or C.line)
end

function SKIN:PaintButtonUp() end

function SKIN:PaintButtonDown() end

function SKIN:PaintMenu(_, width, height) box(sc(4), width, height, C.surfaceHi) end

function SKIN:PaintMenuSpacer(_, width, height) box(0, width, height, C.line) end

function SKIN:PaintMenuOption(panel, width, height)
    if panel.Hovered or panel.Highlight then box(sc(4), width, height, ColorAlpha(C.accent, 90)) end
    if panel:GetChecked() then draw.RoundedBox(sc(3), sc(8), height / 2 - sc(3), sc(6), sc(6), C.accent) end
end

function SKIN:PaintTooltip(_, width, height) box(sc(4), width, height, C.surfaceHi) end

-- Colours Rareload sets itself; any other group is read from the Default skin when a panel asks for
-- it. The engine loads the Default skin after autorun files run, so nothing is copied here.
SKIN.Colours = setmetatable({
    Window = { TitleActive = C.text, TitleInactive = C.text2 },
    Label = { Default = C.text, Bright = C.text, Dark = C.text, Highlight = C.accent },
    Button = { Normal = C.text, Hover = C.text, Down = C.text2, Disabled = C.textOff },
    TooltipText = C.text,
}, {
    __index = function(_, key)
        local default = derma.GetNamedSkin("Default")
        return default and default.Colours[key]
    end
})
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
    local button = vgui.Create("DButton", parent)
    button:SetText("")
    button:SetTall(sc(opts.tall or 32))
    button.label, button.icon = text, opts.icon
    function button:SetLabel(newLabel) self.label = newLabel end

    -- An active toggle button is drawn solid with a pulsing dot.
    function button:SetActive(on) self.active = on end

    button.Paint = function(self, width, height)
        local hover = self:IsEnabled() and hoverAnim(self, self:IsHovered()) or 0
        local fill, textCol
        if not self:IsEnabled() then
            fill, textCol = C.bgDark, C.textOff
        elseif opts.solid or self.active then
            fill, textCol = UI.Mix(col, color_white, hover * 0.15), Color(15, 17, 22)
        else
            fill, textCol = UI.Mix(UI.Mix(C.surface, col, 0.14), col, hover * 0.55), UI.Mix(C.text, color_white, hover)
        end
        if self.Depressed then fill = UI.Mix(fill, color_black, 0.15) end
        box(sc(7), width, height, fill)
        surface.SetFont("Rareload.BodyB")
        local tw = surface.GetTextSize(self.label)
        local is = UI.IconSize(sc(16))
        local iw = self.icon and is + (self.label ~= "" and sc(7) or 0) or 0 -- no gap on an icon-only button
        local contentX = math.floor((width - tw - iw) / 2)
        if self.icon then
            UI.DrawIcon(self.icon, contentX, math.floor((height - is) / 2), is,
                self:IsEnabled() and color_white or C.textOff)
        end
        draw.SimpleText(self.label, "Rareload.BodyB", contentX + iw, math.floor(height / 2), textCol, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        if self.active then
            local dotRadius = sc(3) + sc(1.5) * math.abs(math.sin(RealTime() * 4))
            draw.RoundedBox(dotRadius, sc(12) - dotRadius, height / 2 - dotRadius, dotRadius * 2, dotRadius * 2,
                textCol)
        end
    end
    button.DoClick = function(self)
        surface.PlaySound("ui/buttonclickrelease.wav")
        if onClick then onClick(self) end
    end
    function button:SizeToLabel(pad)
        surface.SetFont("Rareload.BodyB")
        self:SetWide(surface.GetTextSize(self.label) +
            (self.icon and UI.IconSize(sc(16)) + (self.label ~= "" and sc(7) or 0) or 0) + sc(pad or 28))
    end

    return button
end

-- A rounded card. `paint(self, w, h)` draws its content after the background.
function UI.Card(parent, paint, col)
    local panel = vgui.Create("DPanel", parent)
    panel.Paint = function(self, width, height)
        box(sc(10), width, height, col or C.surface)
        if paint then paint(self, width, height) end
    end
    return panel
end

function UI.Label(parent, text, font, col)
    local label = vgui.Create("DLabel", parent)
    label:SetFont(font or "Rareload.Body")
    label:SetTextColor(col or C.text)
    label:SetText(text)
    label:SizeToContents()
    return label
end

-- A text entry with a search icon and a placeholder. onChange(text) runs on every keystroke.
function UI.Search(parent, placeholder, onChange)
    local entry = vgui.Create("DTextEntry", parent)
    entry:SetTall(sc(32))
    entry:SetFont("Rareload.Body")
    entry:SetUpdateOnType(true)
    entry:SetTextInset(sc(28), 0)
    entry.Paint = function(self, width, height)
        box(sc(8), width, height, self:HasFocus() and C.surfaceHi or C.surface)
        UI.DrawIcon("magnifier", sc(8), (height - sc(16)) / 2, sc(16), ColorAlpha(color_white, 160))
        self:DrawTextEntryText(C.text, C.accent, C.text)
        if self:GetValue() == "" then
            draw.SimpleText(placeholder, "Rareload.Body", sc(30), height / 2, C.text3, TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)
        end
    end
    entry.OnValueChange = function(_, value) onChange(value) end
    return entry
end

-- A multi-line or single-line text entry in the kit's style.
function UI.TextEntry(parent, placeholder, multiline)
    local entry = vgui.Create("DTextEntry", parent)
    entry:SetFont(multiline and "Rareload.Mono" or "Rareload.Body")
    entry:SetMultiline(multiline or false)
    entry:SetTall(sc(32))
    entry.Paint = function(self, width, height)
        box(sc(8), width, height, self:HasFocus() and C.surfaceHi or C.surface)
        self:DrawTextEntryText(C.text, C.accent, C.text)
        local hint = self.placeholder or placeholder -- .placeholder: one that changes, set by the caller
        if hint and self:GetValue() == "" and not self:HasFocus() then
            draw.SimpleText(hint, "Rareload.Body", sc(8), multiline and sc(10) or height / 2, C.text3, TEXT_ALIGN_LEFT,
                multiline and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
        end
    end
    return entry
end

-- Equal-width segmented choices. items = { { id, label } }. Returns the panel; :SetSelected(id).
function UI.Chips(parent, items, selected, onSelect)
    local panel = vgui.Create("DPanel", parent)
    panel:SetTall(sc(28))
    panel.Paint = function() end
    panel.selected = selected
    local buttons = {}
    for _, item in ipairs(items) do
        local button = vgui.Create("DButton", panel)
        button:SetText("")
        button.Paint = function(self, width, height)
            local on = panel.selected == item.id
            local hover = hoverAnim(self, self:IsHovered())
            box(sc(6), width, height, on and ColorAlpha(C.accent, 90) or UI.Mix(C.surface, C.surfaceHi, hover))
            draw.SimpleText(UI.Clip(item.label, "Rareload.Small", width - sc(6)), "Rareload.Small", width / 2,
                height / 2,
                on and C.text or C.text2, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        button.DoClick = function()
            panel.selected = item.id
            onSelect(item.id)
        end
        buttons[#buttons + 1] = button
    end
    panel.PerformLayout = function(_, width, height)
        local gap = sc(5)
        local bw = math.floor((width - gap * (#buttons - 1)) / #buttons)
        for i, button in ipairs(buttons) do
            button:SetPos((i - 1) * (bw + gap), 0)
            button:SetSize(i == #buttons and width - (i - 1) * (bw + gap) or bw, height)
        end
    end
    function panel:SetSelected(id) self.selected = id end

    return panel
end

-- A button that opens a menu of options. options = { { id, label } }; get() returns the current id.
function UI.Dropdown(parent, prefix, options, get, onSelect)
    local button = vgui.Create("DButton", parent)
    button:SetText("")
    button:SetTall(sc(28))
    button.Paint = function(self, width, height)
        local hover = hoverAnim(self, self:IsHovered())
        box(sc(6), width, height, UI.Mix(C.surface, C.surfaceHi, hover))
        local current = get()
        local label
        for _, option in ipairs(options) do if option.id == current then label = option.label end end
        draw.RoundedBox(sc(3), sc(10), height / 2 - sc(3), sc(6), sc(6), C.accent)
        draw.SimpleText(UI.Clip((prefix and prefix .. " " or "") .. (label or "?"), "Rareload.Small", width - sc(44)),
            "Rareload.Small", sc(22), height / 2, C.text2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(C.text3)
        draw.NoTexture()
        local arrowX, arrowY = width - sc(14), height / 2
        surface.DrawPoly({
            { x = arrowX - sc(4), y = arrowY - sc(2) }, { x = arrowX + sc(4), y = arrowY - sc(2) },
                { x = arrowX, y = arrowY + sc(3) }
        })
    end
    button.DoClick = function()
        local items = {}
        for i, option in ipairs(options) do
            items[i] = { label = option.label, fn = function() onSelect(option.id) end, checked = option.id == get() }
        end
        UI.Menu(items)
    end
    return button
end

-- Buttons side by side in equal widths, docked to the top of `parent`; hidden ones leave no gap.
function UI.SplitRow(parent, buttons, tall)
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(TOP)
    panel:SetTall(sc(tall))
    panel.Paint = function() end
    for _, button in ipairs(buttons) do button:SetParent(panel) end
    panel.PerformLayout = function(_, width, height)
        local shown = {}
        for _, button in ipairs(buttons) do if button:IsVisible() then shown[#shown + 1] = button end end
        local bw = (width - sc(6) * (#shown - 1)) / math.max(#shown, 1)
        for i, button in ipairs(shown) do
            button:SetPos(math.floor((i - 1) * (bw + sc(6))), 0)
            button:SetSize(math.floor(bw), height)
        end
    end
    return panel
end

-- A popup menu in Rareload's look. items = { { label, fn, icon? (silk name), checked? } }.
function UI.Menu(items)
    local menu = DermaMenu()
    menu:SetSkin("Rareload")
    for _, item in ipairs(items) do
        local opt = menu:AddOption(item.label, item.fn)
        if item.icon then opt:SetIcon("icon16/" .. item.icon .. ".png") end
        if item.checked ~= nil then opt:SetChecked(item.checked) end
        opt:SetTextColor(C.text)
    end
    menu:Open()
    return menu
end

-- A checkbox with a label. value(): current state; onChange(new state).
function UI.Check(parent, label, value, onChange)
    local button = vgui.Create("DButton", parent)
    button:SetText("")
    button:SetTall(sc(24))
    button.value = value
    surface.SetFont("Rareload.Small")
    button:SetWide(surface.GetTextSize(label) + sc(30))
    button.Paint = function(self, width, height)
        local boxSize = sc(16)
        local boxY = (height - boxSize) / 2
        draw.RoundedBox(sc(4), 0, boxY, boxSize, boxSize,
            self.value and C.accent or (self:IsHovered() and C.surfaceHi or C.line))
        if self.value then
            surface.SetDrawColor(color_white)
            surface.DrawLine(sc(4), boxY + boxSize / 2, sc(7), boxY + boxSize - sc(4))
            surface.DrawLine(sc(7), boxY + boxSize - sc(4), boxSize - sc(3), boxY + sc(4))
        end
        draw.SimpleText(label, "Rareload.Small", boxSize + sc(8), height / 2, self:IsEnabled() and C.text2 or C.textOff,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    button.DoClick = function(self)
        self.value = not self.value
        onChange(self.value)
    end
    function button:SetValue(newValue) self.value = newValue end

    return button
end

-- A setting row with a toggle switch. opts = { tooltip, disabled, note } (note: small right text).
-- A switch's track and knob (knob 0 = off .. 1 = on), for the windows' and the spawn menu's switches.
function UI.DrawSwitch(posX, posY, width, height, knob, trackCol, knobCol)
    local inset = height / 9
    draw.RoundedBox(height / 2, posX, posY, width, height, trackCol)
    draw.RoundedBox(height / 2 - inset, math.floor(posX + inset + (width - height) * knob), posY + inset,
        height - 2 * inset, height - 2 * inset,
        knobCol)
end

function UI.Switch(parent, label, value, onChange, opts)
    opts = opts or {}
    local button = vgui.Create("DButton", parent)
    button:SetText("")
    button:SetTall(sc(30))
    button.value = value
    button.knob = value and 1 or 0
    if opts.tooltip then button:SetTooltip(opts.tooltip) end
    button:SetEnabled(not opts.disabled)
    button.Paint = function(self, width, height)
        self.knob = Lerp(FrameTime() * 14, self.knob, self.value and 1 or 0)
        local hover = self:IsEnabled() and hoverAnim(self, self:IsHovered()) or 0
        if hover > 0.01 then box(sc(6), width, height, ColorAlpha(C.surfaceHi, 200 * hover)) end
        local sw, sh = sc(34), sc(18)
        local sx, sy = width - sw - sc(8), (height - sh) / 2
        local on = self:IsEnabled() and C.ok or C.textOff
        UI.DrawSwitch(sx, sy, sw, sh, self.knob, UI.Mix(C.line, on, self.knob), color_white)
        local textCol = self:IsEnabled() and C.text or C.textOff
        local right = sx - sc(8)
        if opts.note then
            surface.SetFont("Rareload.Tiny")
            right = right - surface.GetTextSize(opts.note) - sc(6)
            draw.SimpleText(opts.note, "Rareload.Tiny", sx - sc(8), height / 2, C.text3, TEXT_ALIGN_RIGHT,
                TEXT_ALIGN_CENTER)
        end
        draw.SimpleText(UI.Clip(label, "Rareload.Body", right - sc(8)), "Rareload.Body", sc(8), height / 2, textCol,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    button.DoClick = function(self)
        self.value = not self.value
        surface.PlaySound("ui/buttonclick.wav")
        onChange(self.value)
    end
    return button
end

-- Label/value rows with dividers. rows() returns { { label, value, color? } }; height follows the rows.
function UI.Rows(parent, rows)
    local panel = vgui.Create("DPanel", parent)
    local rh = sc(24)
    panel.Paint = function(self, width, height)
        box(sc(10), width, height, C.surface)
        local items = rows()
        local rowY = sc(6)
        for i, item in ipairs(items) do
            if i > 1 then
                surface.SetDrawColor(ColorAlpha(C.line, 120))
                surface.DrawLine(sc(12), rowY, width - sc(12), rowY)
            end
            draw.SimpleText(item[1], "Rareload.Small", sc(12), rowY + rh / 2, C.text3, TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)
            surface.SetFont("Rareload.Small")
            local lw = surface.GetTextSize(item[1])
            draw.SimpleText(UI.Clip(item[2], "Rareload.Small", width - lw - sc(40)), "Rareload.Small", width - sc(12),
                rowY + rh / 2,
                item[3] or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            rowY = rowY + rh
        end
        local want = #items * rh + sc(12)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    return panel
end

-- A row of stat cards. cards() returns { { label, value (nil = not saved), color } }.
function UI.Stats(parent, cards)
    local panel = vgui.Create("DPanel", parent)
    panel:SetTall(sc(64))
    panel.Paint = function(_, width, height)
        local items = cards()
        local gap = sc(7)
        local cw = (width - gap * (#items - 1)) / #items
        for i, item in ipairs(items) do
            local cellX = (i - 1) * (cw + gap)
            draw.RoundedBox(sc(8), cellX, 0, cw, height, C.surface)
            if item[2] ~= nil then
                draw.SimpleText(tostring(item[2]), "Rareload.Stat", cellX + cw / 2, height * 0.42, item[3] or C.text,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(L("ui.not_saved"), "Rareload.Small", cellX + cw / 2, height * 0.42, C.textOff,
                    TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
            end
            draw.SimpleText(string.upper(item[1]), "Rareload.Tiny", cellX + cw / 2, height * 0.8, C.text3,
                TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
    end
    return panel
end

-- A centered icon, title and hint for empty lists and "select something" panes.
function UI.Empty(parent, icon, title, hint)
    local panel = vgui.Create("DPanel", parent)
    panel:SetMouseInputEnabled(false)
    -- What it says can change while it is shown.
    function panel:SetEmpty(newIcon, newTitle, newHint) icon, title, hint = newIcon, newTitle, newHint end
    panel.Paint = function(_, width, height)
        UI.DrawIcon(icon, width / 2 - sc(16), height / 2 - sc(46), sc(32), ColorAlpha(color_white, 90))
        draw.SimpleText(title, "Rareload.H2", width / 2, height / 2 + sc(4), C.text2, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
        if hint then
            draw.SimpleText(hint, "Rareload.Small", width / 2, height / 2 + sc(28), C.text3, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
    end
    return panel
end

-- A model preview that frames its model and turns slowly.
function UI.Model(parent, model, speed)
    local mp = vgui.Create("DModelPanel", parent)
    mp:SetMouseInputEnabled(false)
    function mp:ShowModel(modelPath)
        modelPath = UI.IsModel(modelPath) and modelPath or "models/error.mdl"
        if self.shown == modelPath then return end
        self.shown = modelPath
        self:SetModel(modelPath)
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
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:SetSkin("Rareload")
    scroll:GetVBar():SetWide(sc(8))
    return scroll
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
        backdrop.Paint = function(_, width, height)
            surface.SetDrawColor(0, 0, 0, 170)
            surface.DrawRect(0, 0, width, height)
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

    frame.Paint = function(self, width, height)
        box(sc(14), width, height, C.bg)
        draw.SimpleText(self.title, "Rareload.Title", sc(18), sc(12), C.accentHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if self.subtitle then
            draw.SimpleText(self.subtitle, "Rareload.Sub", sc(20), sc(40), C.text3, TEXT_ALIGN_LEFT,
                TEXT_ALIGN_TOP)
        end
        surface.SetDrawColor(C.line)
        surface.DrawLine(0, headH, width, headH)
    end

    -- Drag from anywhere in the header, not only the top 24 pixels.
    frame.OnMousePressed = function(self)
        local mouseX, mouseY = self:ScreenToLocal(gui.MouseX(), gui.MouseY())
        if self:GetSizable() and mouseX > self:GetWide() - sc(20) and mouseY > self:GetTall() - sc(20) then
            self.Sizing = { gui.MouseX() - self:GetWide(), gui.MouseY() - self:GetTall() }
            self:MouseCapture(true)
        elseif mouseY < headH then
            self.Dragging = { gui.MouseX() - self.x, gui.MouseY() - self.y }
            self:MouseCapture(true)
        end
    end

    local buttons = {}
    function frame:HeaderButton(text, fn, bopts)
        local button = UI.Button(self, text, fn, bopts)
        button:SizeToLabel(bopts and bopts.pad)
        buttons[#buttons + 1] = button
        self:InvalidateLayout()
        return button
    end

    frame:HeaderButton("", function() frame:Close() end, { style = "danger", icon = "cross", pad = 4 })

    local baseLayout = frame.PerformLayout
    frame.PerformLayout = function(self, width, height)
        if baseLayout then baseLayout(self, width, height) end
        local buttonX = width - sc(14)
        for _, button in ipairs(buttons) do
            if button:IsVisible() then
                buttonX = buttonX - button:GetWide()
                button:SetPos(buttonX, (headH - button:GetTall()) / 2)
                buttonX = buttonX - sc(6)
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
    local dialog = UI.Window({ title = title, w = 460, h = 190, overlay = true })
    dialog:SetSizable(false)
    local text = UI.Label(dialog, body, "Rareload.Body", C.text2)
    text:Dock(TOP)
    text:SetWrap(true)
    text:SetAutoStretchVertical(true)
    local row = vgui.Create("DPanel", dialog)
    row:Dock(BOTTOM)
    row:SetTall(sc(34))
    row.Paint = function() end
    local no = UI.Button(row, L("ui.cancel"), function() dialog:Close() end, { style = "ghost" })
    no:Dock(RIGHT)
    no:SizeToLabel()
    local yes = UI.Button(row, yesLabel or L("ui.confirm"), function()
        dialog:Close()
        onYes()
    end, { style = "danger", solid = true })
    yes:Dock(RIGHT)
    yes:DockMargin(0, 0, sc(8), 0)
    yes:SizeToLabel()
    return dialog
end

function UI.Notify(text, kind)
    notification.AddLegacy(text, kind == "error" and NOTIFY_ERROR or NOTIFY_GENERIC, 3) -- G79
end

-- Toasts ------------------------------------------------------------------------------------------

local KINDS = { info = NOTIFY_GENERIC, ok = NOTIFY_GENERIC, error = NOTIFY_ERROR, hint = NOTIFY_HINT }

RARELOAD.Net.On("toast", function(toast)
    notification.AddLegacy(L(toast.key, unpack(toast.args or {})), KINDS[toast.kind] or NOTIFY_GENERIC, 4)
    surface.PlaySound(toast.kind == "error" and "buttons/button10.wav" or "buttons/button14.wav")
    hook.Run("RareloadToast", toast)
end)

RARELOAD.Net.On("dev.reload", function()
    include("autorun/rareload.lua")
end)

-- Client subcommands of `rareload` (timeline, menu…): the server owns the command and sends them here.
UI.commands = UI.commands or {} -- name -> fn(args)

function UI.Command(name, fn)
    UI.commands[name] = fn
end

RARELOAD.Net.On("cmd", function(payload)
    local fn = UI.commands[payload.name]
    if fn then fn(payload.args or {}) end
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
